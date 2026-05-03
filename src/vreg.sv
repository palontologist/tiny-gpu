`default_nettype none
`timescale 1ns/1ns

// VECTOR REGISTER FILE — Phase 7a (128-bit, 16 registers per thread)
//
// Each thread owns 16 vector registers (v0–v15), each VREG_BITS wide.
// Special read-only registers mirror the GPU thread-context:
//   v13 — %blockIdx  broadcast to all VREG_BITS/32 lanes
//   v14 — %blockDim  broadcast
//   v15 — %threadIdx broadcast
//   v0  — hardwired zero (writes are silently discarded)
//
// Read  : vs1, vs2 and accumulator vacc are captured on the rising edge
//         during the REQUEST pipeline state (core_state == 3'b011).
// Write : vrd is written on the rising edge during the UPDATE pipeline
//         state (core_state == 3'b110), either from vec_alu_out (for
//         vector ALU ops) or lsu_vout (for quad-word vector loads).
//
// Parameters
//   VREG_BITS        — Width of each vector register (must be 128 for the
//                      current vec_alu.sv implementation).
//   NUM_VREG         — Number of vector registers (16).
//   THREADS_PER_BLOCK — Passed in so v15 can hold the correct thread index.
//   THREAD_ID        — Static thread index; initialises %threadIdx (v15).
module vreg #(
    parameter VREG_BITS        = 128,
    parameter NUM_VREG         = 16,
    parameter THREADS_PER_BLOCK = 4,
    parameter THREAD_ID        = 0
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Thread-context (updated live from the block dispatcher)
    input reg [7:0] block_id,
    input reg [2:0] core_state,

    // Decode-stage control signals
    input reg        decoded_vreg_write_enable, // Write vrd this UPDATE
    input reg        decoded_vload,             // Source is lsu_vout, not vec_alu_out
    input reg [3:0]  decoded_vrd_address,       // Destination vector register
    input reg [3:0]  decoded_vrs1_address,      // Source vector register 1
    input reg [3:0]  decoded_vrs2_address,      // Source vector register 2

    // Write-back sources
    input reg [VREG_BITS-1:0] vec_alu_out,  // From vec_alu.sv
    input reg [VREG_BITS-1:0] lsu_vout,     // From lsu.sv (quad-word load)

    // Read outputs (captured in REQUEST, consumed in EXECUTE)
    output reg [VREG_BITS-1:0] vs1,   // Vector source operand 1
    output reg [VREG_BITS-1:0] vs2,   // Vector source operand 2
    output reg [VREG_BITS-1:0] vacc   // Accumulator (= vrd before write-back)
);
    // ---- Register array ----
    reg [VREG_BITS-1:0] vregfile [NUM_VREG-1:0];

    // Number of 32-bit lanes packed into one vector register
    localparam LANES = VREG_BITS / 32;

    integer vk, vl;

    always @(posedge clk) begin
        if (reset) begin
            vs1  <= {VREG_BITS{1'b0}};
            vs2  <= {VREG_BITS{1'b0}};
            vacc <= {VREG_BITS{1'b0}};
            for (vk = 0; vk < NUM_VREG; vk = vk + 1)
                vregfile[vk] <= {VREG_BITS{1'b0}};
            // %blockDim (v14) — broadcast THREADS_PER_BLOCK into every lane
            for (vl = 0; vl < LANES; vl = vl + 1)
                vregfile[14][vl*32 +: 32] <= THREADS_PER_BLOCK[31:0];
            // %threadIdx (v15) — broadcast THREAD_ID into every lane
            for (vl = 0; vl < LANES; vl = vl + 1)
                vregfile[15][vl*32 +: 32] <= THREAD_ID[31:0];
        end else if (enable) begin
            // ---- Keep %blockIdx (v13) current every cycle ----
            for (vl = 0; vl < LANES; vl = vl + 1)
                vregfile[13][vl*32 +: 32] <= {24'b0, block_id};

            // ---- REQUEST: read operands into pipeline registers ----
            if (core_state == 3'b011) begin
                vs1  <= (decoded_vrs1_address == 4'b0) ? {VREG_BITS{1'b0}}
                                                       : vregfile[decoded_vrs1_address];
                vs2  <= (decoded_vrs2_address == 4'b0) ? {VREG_BITS{1'b0}}
                                                       : vregfile[decoded_vrs2_address];
                // vacc reads the destination register BEFORE write-back
                // (needed for accumulate ops like VMADD and VDP4A)
                vacc <= (decoded_vrd_address  == 4'b0) ? {VREG_BITS{1'b0}}
                                                       : vregfile[decoded_vrd_address];
            end

            // ---- UPDATE: write result back to vrd ----
            if (core_state == 3'b110) begin
                // v0 is hardwired to zero — never write
                if (decoded_vreg_write_enable && decoded_vrd_address != 4'b0) begin
                    vregfile[decoded_vrd_address] <= decoded_vload ? lsu_vout
                                                                   : vec_alu_out;
                end
            end
        end
    end
endmodule
