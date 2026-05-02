`default_nettype none
`timescale 1ns/1ns

// REGISTER FILE (RV32: 32 × 32-bit registers per thread — Phase 1)
// x0  hardwired to zero (RISC-V spec)
// x13 = %blockIdx  (read-only GPU extension, updated each dispatch)
// x14 = %blockDim  (read-only GPU extension)
// x15 = %threadIdx (read-only GPU extension)
module registers #(
    parameter THREADS_PER_BLOCK = 4,
    parameter THREAD_ID = 0
) (
    input wire clk,
    input wire reset,
    input wire enable,

    input reg [7:0] block_id,
    input reg [2:0] core_state,

    // Register address inputs (5-bit RV32)
    input reg [4:0] decoded_rd_address,
    input reg [4:0] decoded_rs1_address,
    input reg [4:0] decoded_rs2_address,

    // Write-back control
    input reg        decoded_reg_write_enable,
    input reg [1:0]  decoded_reg_input_mux, // 0=ALU 1=Mem 2=PC+4

    // Write-back data sources
    input reg [31:0] alu_out,
    input reg [31:0] lsu_out,
    input reg [31:0] pc_plus4,  // For JAL / JALR link register

    // Read outputs
    output reg [31:0] rs1,
    output reg [31:0] rs2,
    output reg [31:0] rs3  // rd read before write-back (DP4A accumulator)
);
    localparam REG_SRC_ALU = 2'b00;
    localparam REG_SRC_MEM = 2'b01;
    localparam REG_SRC_PC4 = 2'b10;

    // 32 × 32-bit architectural register file
    reg [31:0] regfile [31:0];

    integer k;
    always @(posedge clk) begin
        if (reset) begin
            rs1 <= 32'b0;
            rs2 <= 32'b0;
            rs3 <= 32'b0;
            for (k = 0; k < 32; k = k + 1)
                regfile[k] <= 32'b0;
            // GPU special-purpose read-only registers
            regfile[13] <= 32'b0;              // %blockIdx  (set at dispatch)
            regfile[14] <= THREADS_PER_BLOCK;  // %blockDim
            regfile[15] <= THREAD_ID;          // %threadIdx
        end else if (enable) begin
            // Keep %blockIdx current every cycle
            regfile[13] <= {24'b0, block_id};

            // Read operands during REQUEST state
            if (core_state == 3'b011) begin
                rs1 <= (decoded_rs1_address == 5'b0) ? 32'b0 : regfile[decoded_rs1_address];
                rs2 <= (decoded_rs2_address == 5'b0) ? 32'b0 : regfile[decoded_rs2_address];
                // rs3 reads the destination register before it is written (for DP4A accumulate)
                rs3 <= (decoded_rd_address  == 5'b0) ? 32'b0 : regfile[decoded_rd_address];
            end

            // Write-back during UPDATE state
            if (core_state == 3'b110) begin
                // x0 is hardwired to zero — never write to it
                if (decoded_reg_write_enable && decoded_rd_address != 5'b0) begin
                    case (decoded_reg_input_mux)
                        REG_SRC_ALU: regfile[decoded_rd_address] <= alu_out;
                        REG_SRC_MEM: regfile[decoded_rd_address] <= lsu_out;
                        REG_SRC_PC4: regfile[decoded_rd_address] <= pc_plus4;
                        default:     regfile[decoded_rd_address] <= alu_out;
                    endcase
                end
            end
        end
    end
endmodule
