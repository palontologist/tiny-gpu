`default_nettype none
`timescale 1ns/1ns

// ARITHMETIC-LOGIC UNIT (RV32IM + INT4 DP4A + FP32 stubs — Phase 1/2/6)
// Supports full RV32IM integer operations plus two custom extension groups:
//   INT4 DP4A  (Phase 2): 8×INT4 signed/unsigned dot-product with accumulate
//   FP32 stubs (Phase 6): add/mul placeholders mapped to Intel FP IP at synthesis
//
// Intel DSP hint: (* use_dsp = "yes" *) on the multiply logic encourages
// Quartus to infer DSP blocks (Intel AI Tensor Accelerator on Agilex).
//
// Each thread in each core has its own ALU instance.
module alu (
    input wire clk,
    input wire reset,
    input wire enable,

    input reg [2:0] core_state,

    input reg [4:0]  decoded_alu_op,
    input reg [1:0]  decoded_pc_src,
    input reg [2:0]  decoded_branch_op,
    input reg        decoded_pc_as_op1,
    input reg        decoded_use_imm,

    input reg [31:0] rs1,
    input reg [31:0] rs2,
    input reg [31:0] rs3,        // Accumulator for DP4A (reads rd before write)
    input reg [31:0] immediate,
    input reg [31:0] pc,         // Current PC for AUIPC / JAL / JALR

    output wire [31:0] alu_out,
    output wire        branch_taken
);
    // ALU op constants — must stay in sync with decoder.sv
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
    localparam ALU_LUI    = 5'd10;
    localparam ALU_MUL    = 5'd11;
    localparam ALU_MULH   = 5'd12;
    localparam ALU_MULHSU = 5'd13;
    localparam ALU_MULHU  = 5'd14;
    localparam ALU_DIV    = 5'd15;
    localparam ALU_DIVU   = 5'd16;
    localparam ALU_REM    = 5'd17;
    localparam ALU_REMU   = 5'd18;
    localparam ALU_DP4A   = 5'd19;
    localparam ALU_DP4AU  = 5'd20;
    localparam ALU_FP_ADD = 5'd21;
    localparam ALU_FP_MUL = 5'd22;

    // Branch condition encodings (funct3)
    localparam BEQ  = 3'b000;
    localparam BNE  = 3'b001;
    localparam BLT  = 3'b100;
    localparam BGE  = 3'b101;
    localparam BLTU = 3'b110;
    localparam BGEU = 3'b111;

    localparam PC_SRC_BRANCH = 2'd1;

    reg [31:0] alu_out_reg;
    reg        branch_taken_reg;
    assign alu_out      = alu_out_reg;
    assign branch_taken = branch_taken_reg;

    // Operand selection
    wire [31:0] op1 = decoded_pc_as_op1 ? pc        : rs1;
    wire [31:0] op2 = decoded_use_imm   ? immediate : rs2;

    // (* use_dsp = "yes" *) — Intel Quartus DSP inference hint for multiply
    wire signed [63:0] mul_ss  = $signed(rs1)         * $signed(rs2);
    wire        [63:0] mul_uu  = rs1                  * rs2;
    wire signed [63:0] mul_su  = $signed(rs1)         * $signed({1'b0, rs2});

    // ---- Phase 2: INT4 DP4A ----
    // Each 32-bit register packs 8 × 4-bit INT4 values (lanes 0..7).
    // Result = rs3 + sum_{k=0}^{7} (rs1[4k+:4] * rs2[4k+:4])
    // Signed version sign-extends each 4-bit product to 8 bits before summing.
    function automatic signed [31:0] dp4a_s;
        input [31:0] a, b, acc;
        integer k;
        reg signed [8:0] prod;
        reg signed [31:0] s;
        begin
            s = $signed(acc);
            for (k = 0; k < 8; k = k + 1) begin
                prod = $signed({{5{a[k*4+3]}}, a[k*4 +: 4]}) *
                       $signed({{5{b[k*4+3]}}, b[k*4 +: 4]});
                s = s + {{23{prod[8]}}, prod};
            end
            dp4a_s = s;
        end
    endfunction

    function automatic [31:0] dp4a_u;
        input [31:0] a, b, acc;
        integer k;
        reg [8:0] prod;
        reg [31:0] s;
        begin
            s = acc;
            for (k = 0; k < 8; k = k + 1) begin
                prod = {5'b0, a[k*4 +: 4]} * {5'b0, b[k*4 +: 4]};
                s = s + {23'b0, prod};
            end
            dp4a_u = s;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            alu_out_reg      <= 32'b0;
            branch_taken_reg <= 1'b0;
        end else if (enable && core_state == 3'b101) begin // EXECUTE state
            branch_taken_reg <= 1'b0;
            case (decoded_alu_op)
                // ---- RV32I integer ----
                ALU_ADD:    alu_out_reg <= op1 + op2;
                ALU_SUB:    alu_out_reg <= op1 - op2;
                ALU_SLL:    alu_out_reg <= op1 << op2[4:0];
                ALU_SLT:    alu_out_reg <= ($signed(op1) < $signed(op2)) ? 32'd1 : 32'd0;
                ALU_SLTU:   alu_out_reg <= (op1 < op2) ? 32'd1 : 32'd0;
                ALU_XOR:    alu_out_reg <= op1 ^ op2;
                ALU_SRL:    alu_out_reg <= op1 >> op2[4:0];
                ALU_SRA:    alu_out_reg <= $signed(op1) >>> op2[4:0];
                ALU_OR:     alu_out_reg <= op1 | op2;
                ALU_AND:    alu_out_reg <= op1 & op2;
                ALU_LUI:    alu_out_reg <= immediate;         // pass-through upper imm
                // ---- RV32M multiply / divide ----
                ALU_MUL:    alu_out_reg <= mul_ss[31:0];
                ALU_MULH:   alu_out_reg <= mul_ss[63:32];
                ALU_MULHSU: alu_out_reg <= mul_su[63:32];
                ALU_MULHU:  alu_out_reg <= mul_uu[63:32];
                ALU_DIV:    alu_out_reg <= (rs2 != 0) ? ($signed(rs1) / $signed(rs2)) : 32'hFFFFFFFF;
                ALU_DIVU:   alu_out_reg <= (rs2 != 0) ? (rs1 / rs2) : 32'hFFFFFFFF;
                ALU_REM:    alu_out_reg <= (rs2 != 0) ? ($signed(rs1) % $signed(rs2)) : rs1;
                ALU_REMU:   alu_out_reg <= (rs2 != 0) ? (rs1 % rs2) : rs1;
                // ---- Phase 2: INT4 dot-product accumulate ----
                ALU_DP4A:   alu_out_reg <= dp4a_s(rs1, rs2, rs3);
                ALU_DP4AU:  alu_out_reg <= dp4a_u(rs1, rs2, rs3);
                // ---- Phase 6: FP32 stubs ----
                // TODO: replace with Intel Floating-Point IP (alt_fp_add / alt_fp_mult)
                //       instantiated via Quartus IP Catalog or Platform Designer.
                ALU_FP_ADD: alu_out_reg <= op1 + op2;  // integer approximation until IP
                ALU_FP_MUL: alu_out_reg <= op1;        // placeholder
                default:    alu_out_reg <= 32'b0;
            endcase

            // ---- Branch condition evaluation ----
            if (decoded_pc_src == PC_SRC_BRANCH) begin
                case (decoded_branch_op)
                    BEQ:  branch_taken_reg <= (rs1 == rs2);
                    BNE:  branch_taken_reg <= (rs1 != rs2);
                    BLT:  branch_taken_reg <= ($signed(rs1) <  $signed(rs2));
                    BGE:  branch_taken_reg <= ($signed(rs1) >= $signed(rs2));
                    BLTU: branch_taken_reg <= (rs1 <  rs2);
                    BGEU: branch_taken_reg <= (rs1 >= rs2);
                    default: branch_taken_reg <= 1'b0;
                endcase
            end
        end
    end
endmodule
