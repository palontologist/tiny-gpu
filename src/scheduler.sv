`default_nettype none
`timescale 1ns/1ns

// SCHEDULER (Phase 3: Sparsity skip + Phase 4: ROB hazard stall)
// Controls the pipeline state machine for one compute core.
//
// Pipeline stages:
//   IDLE → FETCH → DECODE → REQUEST → WAIT → EXECUTE → UPDATE → DONE
//
// Phase 3 — Sparsity skip:
//   If all threads in the warp have zero-valued rs1 AND rs2, and the
//   instruction is a register-write ALU op (not a memory or branch op),
//   the scheduler skips directly from REQUEST to UPDATE, writing zero to rd
//   without consuming an execute cycle.
//
// Phase 4 — ROB hazard stall:
//   Before advancing past REQUEST, the scheduler checks whether either source
//   register has an unresolved in-flight write in the ROB.  If so, the
//   pipeline stalls in REQUEST until the hazard clears.
module scheduler #(
    parameter THREADS_PER_BLOCK = 4,
    parameter ROB_DEPTH         = 16
) (
    input wire clk,
    input wire reset,
    input wire start,

    // Decoded control signals (from decoder)
    input reg        decoded_mem_read_enable,
    input reg        decoded_mem_write_enable,
    input reg        decoded_ret,
    input reg        decoded_reg_write_enable,
    input reg [4:0]  decoded_rd_address,
    input reg [4:0]  decoded_rs1_address,
    input reg [4:0]  decoded_rs2_address,

    // Memory access state
    input reg [2:0] fetcher_state,
    input reg [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

    // Current & next PC
    output reg [7:0] current_pc,
    input  reg [7:0] next_pc [THREADS_PER_BLOCK-1:0],

    // Phase 3 — Sparsity: per-thread zero flags (sampled in REQUEST)
    input reg [THREADS_PER_BLOCK-1:0] rs1_zero,
    input reg [THREADS_PER_BLOCK-1:0] rs2_zero,

    // Phase 4 — ROB hazard / capacity signals
    input wire rob_rs1_pending,  // rs1 has unresolved in-flight write
    input wire rob_rs2_pending,  // rs2 has unresolved in-flight write
    input wire rob_full,         // ROB has no free entries

    // Phase 4 — Signal ROB to allocate entry for this instruction
    output reg rob_alloc_valid,

    // Core execution state
    output reg [2:0] core_state,
    output reg       done,

    // Phase 3 — Sparsity skip signal (to ALU and register file)
    output reg sparse_skip
);
    localparam IDLE    = 3'b000,
               FETCH   = 3'b001,
               DECODE  = 3'b010,
               REQUEST = 3'b011,
               WAIT    = 3'b100,
               EXECUTE = 3'b101,
               UPDATE  = 3'b110,
               DONE    = 3'b111;

    // Phase 3: sparsity skip condition
    // Conservative: skip only when BOTH operands are zero across ALL threads,
    // instruction writes a register, and is not a memory or branch op.
    wire all_rs1_zero    = &rs1_zero;
    wire all_rs2_zero    = &rs2_zero;
    wire sparsity_skip_ok = all_rs1_zero
                         && all_rs2_zero
                         && decoded_reg_write_enable
                         && !decoded_mem_read_enable
                         && !decoded_mem_write_enable
                         && !decoded_ret;

    always @(posedge clk) begin
        if (reset) begin
            current_pc      <= 8'b0;
            core_state      <= IDLE;
            done            <= 1'b0;
            sparse_skip     <= 1'b0;
            rob_alloc_valid <= 1'b0;
        end else begin
            rob_alloc_valid <= 1'b0;
            sparse_skip     <= 1'b0;

            case (core_state)
                IDLE: begin
                    if (start) core_state <= FETCH;
                end

                FETCH: begin
                    // Advance once fetcher has the instruction ready
                    if (fetcher_state == 3'b010) core_state <= DECODE;
                end

                DECODE: begin
                    // Decode is one cycle; move to REQUEST immediately
                    core_state <= REQUEST;
                end

                REQUEST: begin
                    // Phase 4: stall while there is a data hazard or ROB is full
                    if (decoded_reg_write_enable && (rob_full || rob_rs1_pending || rob_rs2_pending)) begin
                        // Remain in REQUEST; retry next cycle
                        core_state <= REQUEST;
                    end else begin
                        // Phase 3: sparsity shortcut — skip execution for all-zero ALU ops
                        if (sparsity_skip_ok) begin
                            sparse_skip <= 1'b1;
                            // Skip WAIT/EXECUTE; go straight to UPDATE (writes zero)
                            core_state  <= UPDATE;
                        end else begin
                            // Normal path: allocate ROB entry if instruction writes a register
                            if (decoded_reg_write_enable)
                                rob_alloc_valid <= 1'b1;
                            core_state <= WAIT;
                        end
                    end
                end

                WAIT: begin
                    // Wait for all LSUs to finish their pending requests
                    begin
                        reg any_lsu_busy;
                        integer i;
                        any_lsu_busy = 1'b0;
                        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                            if (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10)
                                any_lsu_busy = 1'b1;
                        end
                        if (!any_lsu_busy) core_state <= EXECUTE;
                    end
                end

                EXECUTE: begin
                    core_state <= UPDATE;
                end

                UPDATE: begin
                    if (decoded_ret) begin
                        done       <= 1'b1;
                        core_state <= DONE;
                    end else begin
                        // TODO: branch divergence — for now all threads converge on last thread's PC
                        current_pc <= next_pc[THREADS_PER_BLOCK-1];
                        core_state <= FETCH;
                    end
                end

                DONE: begin
                    // Kernel block finished; hold until dispatcher resets this core
                end
            endcase
        end
    end
endmodule
