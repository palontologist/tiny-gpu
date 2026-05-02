`default_nettype none
`timescale 1ns/1ns

// REORDER BUFFER (ROB — Phase 4: Out-of-Order Execution)
// Implements a lightweight Tomasulo-style ROB for load-latency hiding.
// All threads in a warp execute the same instruction (SIMD), so each ROB
// entry covers one warp-level instruction and holds per-thread result data.
//
// Key capabilities:
//   • In-order allocation (tail) and in-order commit (head)
//   • Out-of-order writeback: any in-flight entry can be marked done once
//     its execution unit finishes
//   • Hazard detection: stalls issue when a source register has a pending
//     in-flight write that has not yet been committed
//   • Result forwarding: if the in-flight entry is already done (written back
//     but not yet committed) the value can be forwarded directly
module rob #(
    parameter ROB_DEPTH        = 16,
    parameter THREADS_PER_BLOCK = 4,
    parameter DATA_BITS        = 32
) (
    input wire clk,
    input wire reset,

    // ---- Allocation (from decode / scheduler) ----
    input  wire                       alloc_valid,
    input  wire [4:0]                 alloc_rd,
    input  wire                       alloc_is_load,
    output wire [$clog2(ROB_DEPTH)-1:0] alloc_tag,
    output wire                       alloc_ready,   // ROB has free space

    // ---- Writeback (from execute / LSU) ----
    input  wire                       wb_valid,
    input  wire [$clog2(ROB_DEPTH)-1:0] wb_tag,
    input  wire [DATA_BITS-1:0]       wb_data [THREADS_PER_BLOCK-1:0],

    // ---- Commit (to register file, in-order from head) ----
    output wire                       commit_valid,
    output wire [4:0]                 commit_rd,
    output wire [DATA_BITS-1:0]       commit_data [THREADS_PER_BLOCK-1:0],
    input  wire                       commit_ack,

    // ---- Hazard / forwarding queries (from scheduler) ----
    input  wire [4:0] hazard_rs1,
    input  wire [4:0] hazard_rs2,
    output wire       hazard_rs1_pending,  // rs1 has unresolved in-flight write
    output wire       hazard_rs2_pending,  // rs2 has unresolved in-flight write
    output wire [DATA_BITS-1:0] fwd_rs1 [THREADS_PER_BLOCK-1:0],
    output wire [DATA_BITS-1:0] fwd_rs2 [THREADS_PER_BLOCK-1:0],
    output wire       fwd_rs1_valid,       // forwarded rs1 data is ready
    output wire       fwd_rs2_valid        // forwarded rs2 data is ready
);
    localparam LOG_DEPTH = $clog2(ROB_DEPTH);

    // ROB entry storage
    reg                rob_valid [ROB_DEPTH-1:0];
    reg [4:0]          rob_rd    [ROB_DEPTH-1:0];
    reg                rob_done  [ROB_DEPTH-1:0];
    reg [DATA_BITS-1:0] rob_data [ROB_DEPTH-1:0][THREADS_PER_BLOCK-1:0];

    // Circular buffer pointers
    reg [LOG_DEPTH-1:0] head, tail;
    reg [LOG_DEPTH:0]   count;

    assign alloc_tag   = tail;
    assign alloc_ready = (count < ROB_DEPTH[LOG_DEPTH:0]);

    // ---- Commit from head ----
    assign commit_valid = rob_valid[head] && rob_done[head];
    assign commit_rd    = rob_rd[head];

    genvar gi;
    generate
        for (gi = 0; gi < THREADS_PER_BLOCK; gi = gi + 1) begin : g_commit
            assign commit_data[gi] = rob_data[head][gi];
        end
    endgenerate

    // ---- Hazard / forwarding: combinational linear scan over ROB entries ----
    reg                 rs1_pend, rs2_pend;
    reg                 rs1_fwd_v, rs2_fwd_v;
    reg [LOG_DEPTH-1:0] rs1_newest, rs2_newest;
    integer k;

    always @(*) begin
        rs1_pend   = 1'b0;
        rs2_pend   = 1'b0;
        rs1_fwd_v  = 1'b0;
        rs2_fwd_v  = 1'b0;
        rs1_newest = head;
        rs2_newest = head;
        for (k = 0; k < ROB_DEPTH; k = k + 1) begin
            if (rob_valid[k]) begin
                if (rob_rd[k] == hazard_rs1 && hazard_rs1 != 5'b0) begin
                    rs1_pend   = 1'b1;
                    rs1_newest = k[LOG_DEPTH-1:0];
                    if (rob_done[k]) rs1_fwd_v = 1'b1;
                end
                if (rob_rd[k] == hazard_rs2 && hazard_rs2 != 5'b0) begin
                    rs2_pend   = 1'b1;
                    rs2_newest = k[LOG_DEPTH-1:0];
                    if (rob_done[k]) rs2_fwd_v = 1'b1;
                end
            end
        end
    end

    assign hazard_rs1_pending = rs1_pend && !rs1_fwd_v;
    assign hazard_rs2_pending = rs2_pend && !rs2_fwd_v;
    assign fwd_rs1_valid      = rs1_fwd_v;
    assign fwd_rs2_valid      = rs2_fwd_v;

    genvar gj;
    generate
        for (gj = 0; gj < THREADS_PER_BLOCK; gj = gj + 1) begin : g_fwd
            assign fwd_rs1[gj] = rob_data[rs1_newest][gj];
            assign fwd_rs2[gj] = rob_data[rs2_newest][gj];
        end
    endgenerate

    // ---- Sequential ROB management ----
    integer m;
    always @(posedge clk) begin
        if (reset) begin
            head  <= {LOG_DEPTH{1'b0}};
            tail  <= {LOG_DEPTH{1'b0}};
            count <= {(LOG_DEPTH+1){1'b0}};
            for (m = 0; m < ROB_DEPTH; m = m + 1) begin
                rob_valid[m] <= 1'b0;
                rob_done[m]  <= 1'b0;
                rob_rd[m]    <= 5'b0;
            end
        end else begin
            // Allocate new entry at tail
            if (alloc_valid && alloc_ready) begin
                rob_valid[tail] <= 1'b1;
                rob_rd[tail]    <= alloc_rd;
                rob_done[tail]  <= 1'b0;
                tail  <= (tail == ROB_DEPTH[LOG_DEPTH-1:0] - 1) ? {LOG_DEPTH{1'b0}} : tail + 1;
                count <= count + 1;
            end

            // Writeback: mark entry done and store result
            if (wb_valid) begin
                rob_done[wb_tag] <= 1'b1;
                for (m = 0; m < THREADS_PER_BLOCK; m = m + 1)
                    rob_data[wb_tag][m] <= wb_data[m];
            end

            // Commit from head when done
            if (commit_valid && commit_ack) begin
                rob_valid[head] <= 1'b0;
                rob_done[head]  <= 1'b0;
                head  <= (head == ROB_DEPTH[LOG_DEPTH-1:0] - 1) ? {LOG_DEPTH{1'b0}} : head + 1;
                count <= count - 1;
            end
        end
    end
endmodule
