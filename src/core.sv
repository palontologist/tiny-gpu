`default_nettype none
`timescale 1ns/1ns

// COMPUTE CORE (RV32IM + INT4 + Sparsity + ROB + L1 Cache + 128-bit Vector — Phases 1–5,7)
// Manages one block of threads through the 7-stage pipeline.
// Instantiates: fetcher, decoder, scheduler, ROB, and per-thread
//               ALU/LSU/registers/PC (scalar), L1-cache, vreg/vec_alu (vector).
module core #(
    parameter DATA_MEM_ADDR_BITS    = 8,
    parameter DATA_MEM_DATA_BITS    = 32,  // 32 scalar / 128 vector (VECTOR_ENABLE)
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 32,  // 32-bit RV32I instructions (Phase 1)
    parameter THREADS_PER_BLOCK     = 4,
    parameter ROB_DEPTH             = 16,  // Phase 4: out-of-order reorder buffer depth
    parameter L1_SETS               = 16   // Phase 5: L1 cache sets per thread
) (
    input wire clk,
    input wire reset,

    // Kernel execution
    input  wire start,
    output wire done,

    // Block metadata
    input wire [7:0]                         block_id,
    input wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

    // Program memory
    output reg                             program_mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input  reg                             program_mem_read_ready,
    input  reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,

    // Data memory (one channel per thread — driven by L1 cache miss path)
    output wire [THREADS_PER_BLOCK-1:0]                    data_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0]                   data_mem_read_address  [THREADS_PER_BLOCK-1:0],
    input  reg  [THREADS_PER_BLOCK-1:0]                    data_mem_read_ready,
    input  reg  [DATA_MEM_DATA_BITS-1:0]                   data_mem_read_data     [THREADS_PER_BLOCK-1:0],
    output wire [THREADS_PER_BLOCK-1:0]                    data_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0]                   data_mem_write_address [THREADS_PER_BLOCK-1:0],
    output wire [DATA_MEM_DATA_BITS-1:0]                   data_mem_write_data    [THREADS_PER_BLOCK-1:0],
    input  reg  [THREADS_PER_BLOCK-1:0]                    data_mem_write_ready
);
    // ---- Pipeline state ----
    reg [2:0]  core_state;
    reg [2:0]  fetcher_state;
    reg [31:0] instruction;
    reg [7:0]  current_pc;

    // ---- Per-thread scalar signals ----
    reg  [31:0] rs1         [THREADS_PER_BLOCK-1:0];
    reg  [31:0] rs2         [THREADS_PER_BLOCK-1:0];
    reg  [31:0] rs3         [THREADS_PER_BLOCK-1:0]; // DP4A accumulator
    wire [31:0] alu_out     [THREADS_PER_BLOCK-1:0];
    wire        branch_taken[THREADS_PER_BLOCK-1:0];
    wire [31:0] pc_plus4    [THREADS_PER_BLOCK-1:0];
    wire [7:0]  next_pc     [THREADS_PER_BLOCK-1:0];
    reg  [1:0]  lsu_state   [THREADS_PER_BLOCK-1:0];
    wire [31:0] lsu_out     [THREADS_PER_BLOCK-1:0];

    // ---- Per-thread vector signals (Phase 7) ----
    wire [127:0] vs1         [THREADS_PER_BLOCK-1:0];
    wire [127:0] vs2         [THREADS_PER_BLOCK-1:0];
    wire [127:0] vacc        [THREADS_PER_BLOCK-1:0];
    wire [127:0] vec_alu_out [THREADS_PER_BLOCK-1:0];
    wire [127:0] lsu_vout    [THREADS_PER_BLOCK-1:0];

    // ---- Phase 3: sparsity zero-detection ----
    reg [THREADS_PER_BLOCK-1:0] rs1_zero;
    reg [THREADS_PER_BLOCK-1:0] rs2_zero;
    wire sparse_skip;

    // ---- Decoded scalar control signals ----
    reg [4:0]  decoded_rd_address;
    reg [4:0]  decoded_rs1_address;
    reg [4:0]  decoded_rs2_address;
    reg [31:0] decoded_immediate;
    reg        decoded_use_imm;
    reg        decoded_reg_write_enable;
    reg        decoded_mem_read_enable;
    reg        decoded_mem_write_enable;
    reg [1:0]  decoded_mem_size;
    reg        decoded_mem_sign_extend;
    reg [4:0]  decoded_alu_op;
    reg [1:0]  decoded_reg_input_mux;
    reg [2:0]  decoded_branch_op;
    reg [1:0]  decoded_pc_src;
    reg        decoded_pc_as_op1;
    reg        decoded_ret;

    // ---- Decoded vector control signals (Phase 7) ----
    reg        decoded_vreg_write_enable;
    reg [4:0]  decoded_valu_op;
    reg [3:0]  decoded_vrd_address;
    reg [3:0]  decoded_vrs1_address;
    reg [3:0]  decoded_vrs2_address;

    // Quad-word vector load: triggers lsu_vout → vreg write-back
    wire decoded_vload = decoded_mem_read_enable && (decoded_mem_size == 2'b11);

    // ---- Phase 4: ROB interface ----
    wire                            rob_alloc_valid;
    wire                            rob_alloc_ready;
    wire [$clog2(ROB_DEPTH)-1:0]   rob_alloc_tag;
    wire                            rob_rs1_pending;
    wire                            rob_rs2_pending;
    wire                            rob_full;
    wire                            rob_commit_valid;
    wire [4:0]                      rob_commit_rd;
    wire [DATA_MEM_DATA_BITS-1:0]  rob_commit_data [THREADS_PER_BLOCK-1:0];
    // Writeback: fire during EXECUTE when an ALU/LSU result is ready
    wire rob_wb_valid = (core_state == 3'b101) && decoded_reg_write_enable && !sparse_skip;

    assign rob_full = !rob_alloc_ready;

    // ---- Phase 3: zero detection registered in REQUEST state ----
    genvar i;
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : g_sparse
            always @(posedge clk) begin
                if (core_state == 3'b011) begin // REQUEST
                    rs1_zero[i] <= (rs1[i] == 32'b0);
                    rs2_zero[i] <= (rs2[i] == 32'b0);
                end
            end
        end
    endgenerate

    // ---- Fetcher ----
    fetcher #(
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS)
    ) fetcher_instance (
        .clk(clk), .reset(reset),
        .core_state(core_state),
        .current_pc(current_pc),
        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data),
        .fetcher_state(fetcher_state),
        .instruction(instruction)
    );

    // ---- Decoder ----
    decoder decoder_instance (
        .clk(clk), .reset(reset),
        .core_state(core_state),
        .instruction(instruction),
        .decoded_rd_address(decoded_rd_address),
        .decoded_rs1_address(decoded_rs1_address),
        .decoded_rs2_address(decoded_rs2_address),
        .decoded_immediate(decoded_immediate),
        .decoded_use_imm(decoded_use_imm),
        .decoded_reg_write_enable(decoded_reg_write_enable),
        .decoded_mem_read_enable(decoded_mem_read_enable),
        .decoded_mem_write_enable(decoded_mem_write_enable),
        .decoded_mem_size(decoded_mem_size),
        .decoded_mem_sign_extend(decoded_mem_sign_extend),
        .decoded_alu_op(decoded_alu_op),
        .decoded_reg_input_mux(decoded_reg_input_mux),
        .decoded_branch_op(decoded_branch_op),
        .decoded_pc_src(decoded_pc_src),
        .decoded_pc_as_op1(decoded_pc_as_op1),
        .decoded_ret(decoded_ret),
        // Phase 7 vector outputs
        .decoded_vreg_write_enable(decoded_vreg_write_enable),
        .decoded_valu_op(decoded_valu_op),
        .decoded_vrd_address(decoded_vrd_address),
        .decoded_vrs1_address(decoded_vrs1_address),
        .decoded_vrs2_address(decoded_vrs2_address)
    );

    // ---- Phase 4: Reorder Buffer ----
    rob #(
        .ROB_DEPTH(ROB_DEPTH),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .DATA_BITS(DATA_MEM_DATA_BITS)
    ) rob_instance (
        .clk(clk), .reset(reset),
        .alloc_valid(rob_alloc_valid),
        .alloc_rd(decoded_rd_address),
        .alloc_is_load(decoded_mem_read_enable),
        .alloc_tag(rob_alloc_tag),
        .alloc_ready(rob_alloc_ready),
        .wb_valid(rob_wb_valid),
        .wb_tag(rob_alloc_tag),
        .wb_data(alu_out),
        .commit_valid(rob_commit_valid),
        .commit_rd(rob_commit_rd),
        .commit_data(rob_commit_data),
        .commit_ack(rob_commit_valid), // auto-commit every cycle when ready
        .hazard_rs1(decoded_rs1_address),
        .hazard_rs2(decoded_rs2_address),
        .hazard_rs1_pending(rob_rs1_pending),
        .hazard_rs2_pending(rob_rs2_pending),
        .fwd_rs1(), .fwd_rs2(),
        .fwd_rs1_valid(), .fwd_rs2_valid()
    );

    // ---- Scheduler ----
    scheduler #(
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .ROB_DEPTH(ROB_DEPTH)
    ) scheduler_instance (
        .clk(clk), .reset(reset),
        .start(start),
        .decoded_mem_read_enable(decoded_mem_read_enable),
        .decoded_mem_write_enable(decoded_mem_write_enable),
        .decoded_ret(decoded_ret),
        .decoded_reg_write_enable(decoded_reg_write_enable),
        .decoded_rd_address(decoded_rd_address),
        .decoded_rs1_address(decoded_rs1_address),
        .decoded_rs2_address(decoded_rs2_address),
        .fetcher_state(fetcher_state),
        .lsu_state(lsu_state),
        .current_pc(current_pc),
        .next_pc(next_pc),
        .rs1_zero(rs1_zero),
        .rs2_zero(rs2_zero),
        .rob_rs1_pending(rob_rs1_pending),
        .rob_rs2_pending(rob_rs2_pending),
        .rob_full(rob_full),
        .rob_alloc_valid(rob_alloc_valid),
        .core_state(core_state),
        .done(done),
        .sparse_skip(sparse_skip)
    );

    // ---- Per-thread: scalar ALU/LSU/registers/PC + L1 cache + vector vreg/vec_alu ----
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : threads

            // ------------------------------------------------------------------
            // Phase 5: L1 cache — intercepts LSU memory requests.
            // Raw signals coming OUT of the LSU (before the cache)
            wire lsu_raw_rv;   // read valid
            wire [DATA_MEM_ADDR_BITS-1:0] lsu_raw_ra;   // read address
            wire lsu_raw_wv;   // write valid
            wire [DATA_MEM_ADDR_BITS-1:0] lsu_raw_wa;   // write address
            wire [DATA_MEM_DATA_BITS-1:0] lsu_raw_wd;   // write data
            // Signals coming back FROM the cache TO the LSU
            wire lsu_cache_rr; // read ready
            wire [DATA_MEM_DATA_BITS-1:0] lsu_cache_rd; // read data
            wire lsu_cache_wr; // write ready

            // ------------------------------------------------------------------
            // Scalar ALU
            alu alu_instance (
                .clk(clk), .reset(reset),
                .enable(i < thread_count),
                .core_state(core_state),
                .decoded_alu_op(decoded_alu_op),
                .decoded_pc_src(decoded_pc_src),
                .decoded_branch_op(decoded_branch_op),
                .decoded_pc_as_op1(decoded_pc_as_op1),
                .decoded_use_imm(decoded_use_imm),
                .rs1(rs1[i]),
                .rs2(rs2[i]),
                .rs3(rs3[i]),
                .immediate(decoded_immediate),
                .pc({{(32-8){1'b0}}, current_pc}),
                .alu_out(alu_out[i]),
                .branch_taken(branch_taken[i])
            );

            // ------------------------------------------------------------------
            // LSU — memory interface connects to the L1 cache (not directly
            // to the data-memory controller)
            lsu #(
                .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS)
            ) lsu_instance (
                .clk(clk), .reset(reset),
                .enable(i < thread_count),
                .core_state(core_state),
                .decoded_mem_read_enable(decoded_mem_read_enable),
                .decoded_mem_write_enable(decoded_mem_write_enable),
                .decoded_mem_size(decoded_mem_size),
                .decoded_mem_sign_extend(decoded_mem_sign_extend),
                .rs1(rs1[i]),
                .rs2(rs2[i]),
                // Phase 7c: vector store/load data
                .vrs2(vs2[i][127:0]),
                .lsu_vout(lsu_vout[i]),
                // LSU memory I/O → goes to L1 cache, not directly to controller
                .mem_read_valid(lsu_raw_rv),
                .mem_read_address(lsu_raw_ra),
                .mem_read_ready(lsu_cache_rr),
                .mem_read_data(lsu_cache_rd),
                .mem_write_valid(lsu_raw_wv),
                .mem_write_address(lsu_raw_wa),
                .mem_write_data(lsu_raw_wd),
                .mem_write_ready(lsu_cache_wr),
                .lsu_state(lsu_state[i]),
                .lsu_out(lsu_out[i])
            );

            // ------------------------------------------------------------------
            // Phase 5: L1 cache instance (per-thread)
            l1_cache #(
                .SETS(L1_SETS),
                .ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) cache_instance (
                .clk(clk), .reset(reset),
                // LSU side
                .lsu_read_valid(lsu_raw_rv),
                .lsu_read_address(lsu_raw_ra),
                .lsu_read_ready(lsu_cache_rr),
                .lsu_read_data(lsu_cache_rd),
                .lsu_write_valid(lsu_raw_wv),
                .lsu_write_address(lsu_raw_wa),
                .lsu_write_data(lsu_raw_wd),
                .lsu_write_ready(lsu_cache_wr),
                // Memory-controller side — drives the core's external data ports
                .mem_read_valid(data_mem_read_valid[i]),
                .mem_read_address(data_mem_read_address[i]),
                .mem_read_ready(data_mem_read_ready[i]),
                .mem_read_data(data_mem_read_data[i]),
                .mem_write_valid(data_mem_write_valid[i]),
                .mem_write_address(data_mem_write_address[i]),
                .mem_write_data(data_mem_write_data[i]),
                .mem_write_ready(data_mem_write_ready[i])
            );

            // ------------------------------------------------------------------
            // Scalar register file
            registers #(
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .THREAD_ID(i)
            ) register_instance (
                .clk(clk), .reset(reset),
                .enable(i < thread_count),
                .block_id(block_id),
                .core_state(core_state),
                // Phase 3: suppress scalar write on sparsity skip (result = 0)
                .decoded_reg_write_enable(decoded_reg_write_enable && !sparse_skip),
                .decoded_reg_input_mux(decoded_reg_input_mux),
                .decoded_rd_address(decoded_rd_address),
                .decoded_rs1_address(decoded_rs1_address),
                .decoded_rs2_address(decoded_rs2_address),
                .alu_out(sparse_skip ? 32'b0 : alu_out[i]),
                .lsu_out(lsu_out[i]),
                .pc_plus4(pc_plus4[i]),
                .rs1(rs1[i]),
                .rs2(rs2[i]),
                .rs3(rs3[i])
            );

            // ------------------------------------------------------------------
            // Program counter
            pc #(
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
            ) pc_instance (
                .clk(clk), .reset(reset),
                .enable(i < thread_count),
                .core_state(core_state),
                .decoded_pc_src(decoded_pc_src),
                .branch_taken(branch_taken[i]),
                .alu_out(alu_out[i]),
                .current_pc(current_pc),
                .next_pc(next_pc[i]),
                .pc_plus4(pc_plus4[i])
            );

            // ------------------------------------------------------------------
            // Phase 7a: Vector register file
            vreg #(
                .VREG_BITS(128),
                .NUM_VREG(16),
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .THREAD_ID(i)
            ) vreg_instance (
                .clk(clk), .reset(reset),
                .enable(i < thread_count),
                .block_id(block_id),
                .core_state(core_state),
                .decoded_vreg_write_enable(decoded_vreg_write_enable && !sparse_skip),
                .decoded_vload(decoded_vload),
                .decoded_vrd_address(decoded_vrd_address),
                .decoded_vrs1_address(decoded_vrs1_address),
                .decoded_vrs2_address(decoded_vrs2_address),
                .vec_alu_out(vec_alu_out[i]),
                .lsu_vout(lsu_vout[i]),
                .vs1(vs1[i]),
                .vs2(vs2[i]),
                .vacc(vacc[i])
            );

            // ------------------------------------------------------------------
            // Phase 7b: Vector ALU
            vec_alu valu_instance (
                .clk(clk), .reset(reset),
                .enable(i < thread_count),
                .core_state(core_state),
                .decoded_valu_op(decoded_valu_op),
                .vs1(vs1[i]),
                .vs2(vs2[i]),
                .vacc(vacc[i]),
                .vec_alu_out(vec_alu_out[i])
            );

        end // threads generate
    endgenerate
endmodule
