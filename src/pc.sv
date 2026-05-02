`default_nettype none
`timescale 1ns/1ns

// PROGRAM COUNTER (RV32I branch / jump semantics — Phase 1)
// Supports:
//   PC+4   (next sequential instruction)
//   BRANCH (conditional: PC + B-imm when branch_taken)
//   JAL    (unconditional: PC + J-imm, computed by ALU)
//   JALR   (register-indirect: (rs1 + I-imm) & ~1, computed by ALU)
//
// NOTE: the program memory uses word-addressed PCs (each address = one 32-bit
// instruction), so "PC+4" in byte-space maps to "PC+1" here.  alu_out that
// comes from JAL/JALR carries a word-offset target as well (imm already
// divided by 4 in the assembler / compiler, or kept as word offset by
// convention in this implementation).
module pc #(
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire enable,

    input reg [2:0] core_state,

    // Decoded PC source selector
    input reg [1:0] decoded_pc_src,

    // Branch outcome from ALU
    input reg        branch_taken,

    // ALU result carries branch / jump target address (word-addressed)
    input reg [31:0] alu_out,

    // Current PC (word-addressed)
    input reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,

    output reg [PROGRAM_MEM_ADDR_BITS-1:0] next_pc,
    output reg [31:0] pc_plus4   // PC+4 (word-addressed +1) for link register
);
    localparam PC_SRC_NEXT   = 2'd0;
    localparam PC_SRC_BRANCH = 2'd1;
    localparam PC_SRC_JAL    = 2'd2;
    localparam PC_SRC_JALR   = 2'd3;

    always @(posedge clk) begin
        if (reset) begin
            next_pc  <= {PROGRAM_MEM_ADDR_BITS{1'b0}};
            pc_plus4 <= 32'b0;
        end else if (enable && core_state == 3'b101) begin // EXECUTE state
            // Link value: word-addressed PC + 1 (= byte PC + 4)
            pc_plus4 <= {{(32-PROGRAM_MEM_ADDR_BITS){1'b0}}, current_pc} + 32'd1;

            case (decoded_pc_src)
                PC_SRC_NEXT: begin
                    next_pc <= current_pc + 1;
                end
                PC_SRC_BRANCH: begin
                    // alu_out holds branch target (PC + B-imm, word-addressed)
                    next_pc <= branch_taken
                             ? alu_out[PROGRAM_MEM_ADDR_BITS-1:0]
                             : current_pc + 1;
                end
                PC_SRC_JAL: begin
                    // alu_out = PC + J-imm (word-addressed)
                    next_pc <= alu_out[PROGRAM_MEM_ADDR_BITS-1:0];
                end
                PC_SRC_JALR: begin
                    // alu_out = rs1 + I-imm; clear bit 0 per RV32I spec
                    next_pc <= {alu_out[PROGRAM_MEM_ADDR_BITS-1:1], 1'b0};
                end
                default: begin
                    next_pc <= current_pc + 1;
                end
            endcase
        end
    end
endmodule
