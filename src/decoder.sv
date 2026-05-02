`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION DECODER (RV32IM + INT4 + FP32 Extensions — Phase 1/2/6)
// Decodes a 32-bit RISC-V instruction into control signals.
// Custom extensions:
//   CUSTOM0 (opcode 0001011) — thread RET
//   CUSTOM1 (opcode 0101011) — INT4 DP4A / FP32 ops
module decoder (
    input wire clk,
    input wire reset,

    input reg [2:0]  core_state,
    input reg [31:0] instruction,

    // Register addresses (5-bit RV32)
    output reg [4:0] decoded_rd_address,
    output reg [4:0] decoded_rs1_address,
    output reg [4:0] decoded_rs2_address,

    // Sign-extended 32-bit immediate
    output reg [31:0] decoded_immediate,

    // Control signals
    output reg        decoded_use_imm,           // Use immediate as ALU operand 2
    output reg        decoded_reg_write_enable,  // Write result to rd
    output reg        decoded_mem_read_enable,   // Load instruction
    output reg        decoded_mem_write_enable,  // Store instruction
    output reg [1:0]  decoded_mem_size,          // 0=byte 1=halfword 2=word
    output reg        decoded_mem_sign_extend,   // Sign-extend loaded byte/halfword
    output reg [4:0]  decoded_alu_op,            // ALU operation selector
    output reg [1:0]  decoded_reg_input_mux,     // 0=ALU 1=Mem 2=PC+4
    output reg [2:0]  decoded_branch_op,         // Branch condition (funct3)
    output reg [1:0]  decoded_pc_src,            // 0=PC+4 1=branch 2=JAL 3=JALR
    output reg        decoded_pc_as_op1,         // Use PC as ALU op1 (AUIPC/JAL/JALR)
    output reg        decoded_ret                // Thread done (custom RET)
);

    // ---- RV32I standard opcodes ----
    localparam OP_LOAD    = 7'b0000011;
    localparam OP_CUSTOM0 = 7'b0001011; // Thread RET
    localparam OP_OP_IMM  = 7'b0010011;
    localparam OP_AUIPC   = 7'b0010111;
    localparam OP_STORE   = 7'b0100011;
    localparam OP_CUSTOM1 = 7'b0101011; // INT4 / FP32 custom ops
    localparam OP_OP      = 7'b0110011;
    localparam OP_LUI     = 7'b0110111;
    localparam OP_BRANCH  = 7'b1100011;
    localparam OP_JALR    = 7'b1100111;
    localparam OP_JAL     = 7'b1101111;
    localparam OP_SYSTEM  = 7'b1110011; // ECALL/EBREAK treated as NOP

    // ---- ALU operation codes (must match alu.sv) ----
    localparam ALU_ADD    = 5'd0;
    localparam ALU_SUB    = 5'd1;
    localparam ALU_SLL    = 5'd2;
    localparam ALU_SLT    = 5'd3;
    localparam ALU_SLTU   = 5'd4;
    localparam ALU_XOR    = 5'd5;
    localparam ALU_SRL    = 5'd6;
    localparam ALU_SRA    = 5'd7;
    localparam ALU_OR     = 5'd8;
    localparam ALU_AND    = 5'd9;
    localparam ALU_LUI    = 5'd10; // pass-through immediate
    localparam ALU_MUL    = 5'd11;
    localparam ALU_MULH   = 5'd12;
    localparam ALU_MULHSU = 5'd13;
    localparam ALU_MULHU  = 5'd14;
    localparam ALU_DIV    = 5'd15;
    localparam ALU_DIVU   = 5'd16;
    localparam ALU_REM    = 5'd17;
    localparam ALU_REMU   = 5'd18;
    localparam ALU_DP4A   = 5'd19; // Phase 2: signed INT4 dot-product accumulate
    localparam ALU_DP4AU  = 5'd20; // Phase 2: unsigned INT4 dot-product accumulate
    localparam ALU_FP_ADD = 5'd21; // Phase 6: FP32 add stub
    localparam ALU_FP_MUL = 5'd22; // Phase 6: FP32 multiply stub

    // ---- PC source select ----
    localparam PC_SRC_NEXT   = 2'd0;
    localparam PC_SRC_BRANCH = 2'd1;
    localparam PC_SRC_JAL    = 2'd2;
    localparam PC_SRC_JALR   = 2'd3;

    // ---- reg_input_mux select ----
    localparam REG_SRC_ALU   = 2'b00;
    localparam REG_SRC_MEM   = 2'b01;
    localparam REG_SRC_PC4   = 2'b10;

    // Instruction field aliases
    wire [6:0] opcode = instruction[6:0];
    wire [2:0] funct3 = instruction[14:12];
    wire [6:0] funct7 = instruction[31:25];
    wire [4:0] rd     = instruction[11:7];
    wire [4:0] rs1    = instruction[19:15];
    wire [4:0] rs2    = instruction[24:20];

    // Immediate formats
    wire [31:0] imm_i = {{20{instruction[31]}}, instruction[31:20]};
    wire [31:0] imm_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
    wire [31:0] imm_b = {{19{instruction[31]}}, instruction[31], instruction[7],
                          instruction[30:25], instruction[11:8], 1'b0};
    wire [31:0] imm_u = {instruction[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                          instruction[20], instruction[30:21], 1'b0};

    always @(posedge clk) begin
        if (reset) begin
            decoded_rd_address      <= 5'b0;
            decoded_rs1_address     <= 5'b0;
            decoded_rs2_address     <= 5'b0;
            decoded_immediate       <= 32'b0;
            decoded_use_imm         <= 1'b0;
            decoded_reg_write_enable<= 1'b0;
            decoded_mem_read_enable <= 1'b0;
            decoded_mem_write_enable<= 1'b0;
            decoded_mem_size        <= 2'b10;
            decoded_mem_sign_extend <= 1'b1;
            decoded_alu_op          <= ALU_ADD;
            decoded_reg_input_mux   <= REG_SRC_ALU;
            decoded_branch_op       <= 3'b0;
            decoded_pc_src          <= PC_SRC_NEXT;
            decoded_pc_as_op1       <= 1'b0;
            decoded_ret             <= 1'b0;
        end else if (core_state == 3'b010) begin // DECODE state
            // Common register fields
            decoded_rd_address  <= rd;
            decoded_rs1_address <= rs1;
            decoded_rs2_address <= rs2;

            // Default all control outputs; individual cases override selectively
            decoded_immediate       <= 32'b0;
            decoded_use_imm         <= 1'b0;
            decoded_reg_write_enable<= 1'b0;
            decoded_mem_read_enable <= 1'b0;
            decoded_mem_write_enable<= 1'b0;
            decoded_mem_size        <= 2'b10;
            decoded_mem_sign_extend <= 1'b1;
            decoded_alu_op          <= ALU_ADD;
            decoded_reg_input_mux   <= REG_SRC_ALU;
            decoded_branch_op       <= funct3;
            decoded_pc_src          <= PC_SRC_NEXT;
            decoded_pc_as_op1       <= 1'b0;
            decoded_ret             <= 1'b0;

            case (opcode)
                // ---- LUI: rd = imm_u ----
                OP_LUI: begin
                    decoded_immediate       <= imm_u;
                    decoded_use_imm         <= 1'b1;
                    decoded_reg_write_enable<= 1'b1;
                    decoded_alu_op          <= ALU_LUI;
                end
                // ---- AUIPC: rd = PC + imm_u ----
                OP_AUIPC: begin
                    decoded_immediate       <= imm_u;
                    decoded_use_imm         <= 1'b1;
                    decoded_reg_write_enable<= 1'b1;
                    decoded_alu_op          <= ALU_ADD;
                    decoded_pc_as_op1       <= 1'b1;
                end
                // ---- JAL: rd = PC+4, PC = PC + imm_j ----
                OP_JAL: begin
                    decoded_immediate       <= imm_j;
                    decoded_use_imm         <= 1'b1;
                    decoded_reg_write_enable<= 1'b1;
                    decoded_alu_op          <= ALU_ADD;  // target = PC + J-imm
                    decoded_pc_as_op1       <= 1'b1;
                    decoded_pc_src          <= PC_SRC_JAL;
                    decoded_reg_input_mux   <= REG_SRC_PC4;
                end
                // ---- JALR: rd = PC+4, PC = (rs1 + imm_i) & ~1 ----
                OP_JALR: begin
                    decoded_immediate       <= imm_i;
                    decoded_use_imm         <= 1'b1;
                    decoded_reg_write_enable<= 1'b1;
                    decoded_alu_op          <= ALU_ADD;  // target = rs1 + I-imm
                    decoded_pc_src          <= PC_SRC_JALR;
                    decoded_reg_input_mux   <= REG_SRC_PC4;
                end
                // ---- BRANCH: PC = PC + imm_b if condition holds ----
                OP_BRANCH: begin
                    decoded_immediate  <= imm_b;
                    decoded_use_imm    <= 1'b1;
                    decoded_alu_op     <= ALU_ADD;   // branch target = PC + B-imm
                    decoded_pc_as_op1  <= 1'b1;
                    decoded_pc_src     <= PC_SRC_BRANCH;
                    decoded_branch_op  <= funct3;
                end
                // ---- LOAD: rd = mem[rs1 + imm_i] ----
                OP_LOAD: begin
                    decoded_immediate       <= imm_i;
                    decoded_use_imm         <= 1'b1;
                    decoded_reg_write_enable<= 1'b1;
                    decoded_mem_read_enable <= 1'b1;
                    decoded_alu_op          <= ALU_ADD;  // EA = rs1 + I-imm
                    decoded_reg_input_mux   <= REG_SRC_MEM;
                    decoded_mem_size        <= funct3[1:0];
                    decoded_mem_sign_extend <= ~funct3[2];
                end
                // ---- STORE: mem[rs1 + imm_s] = rs2 ----
                OP_STORE: begin
                    decoded_immediate       <= imm_s;
                    decoded_use_imm         <= 1'b1;
                    decoded_mem_write_enable<= 1'b1;
                    decoded_alu_op          <= ALU_ADD;  // EA = rs1 + S-imm
                    decoded_mem_size        <= funct3[1:0];
                end
                // ---- OP-IMM: rd = rs1 op imm_i ----
                OP_OP_IMM: begin
                    decoded_use_imm         <= 1'b1;
                    decoded_reg_write_enable<= 1'b1;
                    case (funct3)
                        3'b000: begin
                            decoded_immediate <= imm_i;
                            decoded_alu_op    <= ALU_ADD;
                        end
                        3'b001: begin // SLLI
                            decoded_immediate <= {27'b0, rs2}; // shamt in rs2 field
                            decoded_alu_op    <= ALU_SLL;
                        end
                        3'b010: begin
                            decoded_immediate <= imm_i;
                            decoded_alu_op    <= ALU_SLT;
                        end
                        3'b011: begin
                            decoded_immediate <= imm_i;
                            decoded_alu_op    <= ALU_SLTU;
                        end
                        3'b100: begin
                            decoded_immediate <= imm_i;
                            decoded_alu_op    <= ALU_XOR;
                        end
                        3'b101: begin // SRLI / SRAI
                            decoded_immediate <= {27'b0, rs2}; // shamt
                            decoded_alu_op    <= funct7[5] ? ALU_SRA : ALU_SRL;
                        end
                        3'b110: begin
                            decoded_immediate <= imm_i;
                            decoded_alu_op    <= ALU_OR;
                        end
                        3'b111: begin
                            decoded_immediate <= imm_i;
                            decoded_alu_op    <= ALU_AND;
                        end
                    endcase
                end
                // ---- OP (R-type): RV32I + RV32M ----
                OP_OP: begin
                    decoded_reg_write_enable <= 1'b1;
                    if (funct7 == 7'b0000001) begin
                        // RV32M multiply / divide
                        case (funct3)
                            3'b000: decoded_alu_op <= ALU_MUL;
                            3'b001: decoded_alu_op <= ALU_MULH;
                            3'b010: decoded_alu_op <= ALU_MULHSU;
                            3'b011: decoded_alu_op <= ALU_MULHU;
                            3'b100: decoded_alu_op <= ALU_DIV;
                            3'b101: decoded_alu_op <= ALU_DIVU;
                            3'b110: decoded_alu_op <= ALU_REM;
                            3'b111: decoded_alu_op <= ALU_REMU;
                        endcase
                    end else begin
                        // RV32I integer arithmetic
                        case (funct3)
                            3'b000: decoded_alu_op <= funct7[5] ? ALU_SUB : ALU_ADD;
                            3'b001: decoded_alu_op <= ALU_SLL;
                            3'b010: decoded_alu_op <= ALU_SLT;
                            3'b011: decoded_alu_op <= ALU_SLTU;
                            3'b100: decoded_alu_op <= ALU_XOR;
                            3'b101: decoded_alu_op <= funct7[5] ? ALU_SRA : ALU_SRL;
                            3'b110: decoded_alu_op <= ALU_OR;
                            3'b111: decoded_alu_op <= ALU_AND;
                        endcase
                    end
                end
                // ---- CUSTOM0: Thread RET ----
                OP_CUSTOM0: begin
                    decoded_ret <= 1'b1;
                end
                // ---- CUSTOM1: INT4 / FP32 ops (Phase 2 / 6) ----
                OP_CUSTOM1: begin
                    decoded_reg_write_enable <= 1'b1;
                    case (funct3)
                        3'b000: decoded_alu_op <= ALU_DP4A;   // signed INT4 DP4A
                        3'b001: decoded_alu_op <= ALU_DP4AU;  // unsigned INT4 DP4A
                        3'b010: decoded_alu_op <= ALU_FP_ADD; // FP32 add stub
                        3'b011: decoded_alu_op <= ALU_FP_MUL; // FP32 mul stub
                        default: decoded_alu_op <= ALU_ADD;
                    endcase
                end
                // ---- SYSTEM: treat as NOP (ECALL / EBREAK) ----
                OP_SYSTEM: begin
                    // no-op
                end
                // ---- Default: NOP ----
                default: begin
                    // no-op
                end
            endcase
        end
    end
endmodule
