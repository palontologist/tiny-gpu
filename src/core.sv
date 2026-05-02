`default_nettype none
`timescale 1ns/1ns

// COMPUTE CORE (RV32IM + INT4 + Sparsity + ROB — Phases 1–4)
// Manages one block of threads through the 7-stage pipeline.
// Instantiates: fetcher, decoder, scheduler, ROB, and per-thread ALU/LSU/registers/PC.
module core #(
    parameter DATA_MEM_ADDR_BITS    = 8,
    parameter DATA_MEM_DATA_BITS    = 32,  // 32-bit data words (Phase 1)
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 32,  // 32-bit RV32I instructions (Phase 1)
    parameter THREADS_PER_BLOCK     = 4,
    parameter ROB_DEPTH             = 16   // Phase 4: out-of-order reorder buffer depth
) (
    input wire clk,
    input wire reset,

    // Kernel execution
    input  wire start,
    output wire done,

    // Block metadata
    input wire [7:0]                      block_id,
    input wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

    // Program memory
    output reg                             program_mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input  reg                             program_mem_read_ready,
    input  reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,

    // Data memory (one channel per thread)
    output reg [THREADS_PER_BLOCK-1:0]        data_mem_read_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0]        data_mem_read_address  [THREADS_PER_BLOCK-1:0],
    input  reg [THREADS_PER_BLOCK-1:0]        data_mem_read_ready,
    input  reg [DATA_MEM_DATA_BITS-1:0]        data_mem_read_data     [THREADS_PER_BLOCK-1:0],
    output reg [THREADS_PER_BLOCK-1:0]        data_mem_write_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0]        data_mem_write_address [THREADS_PER_BLOCK-1:0],
    output reg [DATA_MEM_DATA_BITS-1:0]        data_mem_write_data    [THREADS_PER_BLOCK-1:0],
    input  reg [THREADS_PER_BLOCK-1:0]        data_mem_write_ready
);
    // ---- Pipeline state ----
    reg [2:0]  core_state;
    reg [2:0]  fetcher_state;
    reg [31:0] instruction;
    reg [7:0]  current_pc;

    // ---- Per-thread signals ----
    reg  [31:0] rs1         [THREADS_PER_BLOCK-1:0];
    reg  [31:0] rs2         [THREADS_PER_BLOCK-1:0];
    reg  [31:0] rs3         [THREADS_PER_BLOCK-1:0]; // DP4A accumulator
    wire [31:0] alu_out     [THREADS_PER_BLOCK-1:0];
    wire        branch_taken[THREADS_PER_BLOCK-1:0];
    wire [31:0] pc_plus4    [THREADS_PER_BLOCK-1:0];
    wire [7:0]  next_pc     [THREADS_PER_BLOCK-1:0];
    reg  [1:0]  lsu_state   [THREADS_PER_BLOCK-1:0];
    wire [31:0] lsu_out     [THREADS_PER_BLOCK-1:0];

    // ---- Phase 3: sparsity zero-detection ----
    reg [THREADS_PER_BLOCK-1:0] rs1_zero;
    reg [THREADS_PER_BLOCK-1:0] rs2_zero;
    wire sparse_skip;

    // ---- Decoded control signals ----
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
        .decoded_ret(decoded_ret)
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

    // ---- Per-thread: ALU, LSU, register file, PC ----
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : threads
            // ALU
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

            // LSU
            lsu lsu_instance (
                .clk(clk), .reset(reset),
                .enable(i < thread_count),
                .core_state(core_state),
                .decoded_mem_read_enable(decoded_mem_read_enable),
                .decoded_mem_write_enable(decoded_mem_write_enable),
                .decoded_mem_size(decoded_mem_size),
                .decoded_mem_sign_extend(decoded_mem_sign_extend),
                .rs1(rs1[i]),
                .rs2(rs2[i]),
                .mem_read_valid(data_mem_read_valid[i]),
                .mem_read_address(data_mem_read_address[i]),
                .mem_read_ready(data_mem_read_ready[i]),
                .mem_read_data(data_mem_read_data[i]),
                .mem_write_valid(data_mem_write_valid[i]),
                .mem_write_address(data_mem_write_address[i]),
                .mem_write_data(data_mem_write_data[i]),
                .mem_write_ready(data_mem_write_ready[i]),
                .lsu_state(lsu_state[i]),
                .lsu_out(lsu_out[i])
            );

            // Register file
            registers #(
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .THREAD_ID(i)
            ) register_instance (
                .clk(clk), .reset(reset),
                .enable(i < thread_count),
                .block_id(block_id),
                .core_state(core_state),
                // Phase 3: suppress register write on sparse skip (result is zero)
                .decoded_reg_write_enable(decoded_reg_write_enable && !sparse_skip),
                .decoded_reg_input_mux(decoded_reg_input_mux),
                .decoded_rd_address(decoded_rd_address),
                .decoded_rs1_address(decoded_rs1_address),
                .decoded_rs2_address(decoded_rs2_address),
                // Phase 3: write zero when sparsity skip is active
                .alu_out(sparse_skip ? 32'b0 : alu_out[i]),
                .lsu_out(lsu_out[i]),
                .pc_plus4(pc_plus4[i]),
                .rs1(rs1[i]),
                .rs2(rs2[i]),
                .rs3(rs3[i])
            );

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
        end
    endgenerate
endmodule
