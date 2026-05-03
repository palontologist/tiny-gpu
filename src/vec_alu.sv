`default_nettype none
`timescale 1ns/1ns

// VECTOR ALU — Phase 7b (128-bit packed SIMD, 8 operations)
//
// Operates on 128-bit vector registers produced by vreg.sv.
// All operations treat the 128-bit operands as packed lanes of a fixed
// element width; the lane layout matches the CUSTOM2 instruction encoding
// (decoded_valu_op == funct3[2:0] from CUSTOM2 opcode 7'b1001011).
//
// Operation table (decoded_valu_op):
//   5'd0  VADD_I8   — 16 × INT8 packed add           vs1 + vs2
//   5'd1  VMUL_I8   — 16 × INT8 packed multiply-low  (vs1 * vs2)[7:0]
//   5'd2  VMADD_I8  — 16 × INT8 multiply-accumulate  vacc + vs1 * vs2 (trunc 8-bit)
//   5'd3  VDP4A_I4  — 4  × (8 × INT4 signed DP4A)   4 parallel 32-bit accumulators
//   5'd4  VADD_F32  — 4  × FP32 add stub (integer approx until Intel FP IP)
//   5'd5  VMUL_F32  — 4  × FP32 multiply stub (pass-through placeholder)
//   5'd6  VMADD_F32 — 4  × FP32 fused multiply-add stub
//   5'd7  VPREFETCH — hint (no result; output = vs1 for address pass-through)
//
// Intel DSP inference hint:
//   (* use_dsp = "yes" *) is placed on all packed-multiply paths so that
//   Quartus infers DSP blocks (Intel AI Tensor Accelerator on Agilex).
//
// Each thread in each core has its own vec_alu instance.
module vec_alu (
    input wire clk,
    input wire reset,
    input wire enable,

    input reg [2:0]  core_state,      // Executes in EXECUTE state (3'b101)
    input reg [4:0]  decoded_valu_op, // Operation selector

    input reg [127:0] vs1,   // Vector source operand 1
    input reg [127:0] vs2,   // Vector source operand 2
    input reg [127:0] vacc,  // Accumulator (= vrd before write-back)

    output wire [127:0] vec_alu_out  // Result
);
    // ---- Operation codes (must match decoder.sv CUSTOM2 funct3 mapping) ----
    localparam VALU_VADD_I8   = 5'd0;
    localparam VALU_VMUL_I8   = 5'd1;
    localparam VALU_VMADD_I8  = 5'd2;
    localparam VALU_VDP4A_I4  = 5'd3;
    localparam VALU_VADD_F32  = 5'd4;
    localparam VALU_VMUL_F32  = 5'd5;
    localparam VALU_VMADD_F32 = 5'd6;
    localparam VALU_VPREFETCH = 5'd7;

    reg [127:0] result_reg;
    assign vec_alu_out = result_reg;

    // ---- Phase 7 INT8 helpers ----
    // 16 × INT8 packed add
    function automatic [127:0] vadd_i8;
        input [127:0] a, b;
        integer ii;
        begin
            vadd_i8 = 128'b0;
            for (ii = 0; ii < 16; ii = ii + 1)
                vadd_i8[ii*8 +: 8] = a[ii*8 +: 8] + b[ii*8 +: 8];
        end
    endfunction

    // 16 × INT8 packed multiply-low (lower 8 bits of 16-bit product)
    // (* use_dsp = "yes" *)
    function automatic [127:0] vmul_i8;
        input [127:0] a, b;
        integer ii;
        reg [15:0] prod;
        begin
            vmul_i8 = 128'b0;
            for (ii = 0; ii < 16; ii = ii + 1) begin
                prod = {8'b0, a[ii*8 +: 8]} * {8'b0, b[ii*8 +: 8]};
                vmul_i8[ii*8 +: 8] = prod[7:0];
            end
        end
    endfunction

    // 16 × INT8 multiply-accumulate; truncate product to 8 bits before add
    // (* use_dsp = "yes" *)
    function automatic [127:0] vmadd_i8;
        input [127:0] a, b, acc;
        integer ii;
        reg [15:0] prod;
        begin
            vmadd_i8 = 128'b0;
            for (ii = 0; ii < 16; ii = ii + 1) begin
                prod = {8'b0, a[ii*8 +: 8]} * {8'b0, b[ii*8 +: 8]};
                vmadd_i8[ii*8 +: 8] = acc[ii*8 +: 8] + prod[7:0];
            end
        end
    endfunction

    // ---- Phase 7 VDP4A_I4 ----
    // 4 parallel lanes, each lane = 8 × INT4 signed dot-product with 32-bit
    // accumulation (extends the scalar ALU_DP4A from Phase 2 to 4× lanes).
    // (* use_dsp = "yes" *)
    function automatic signed [31:0] dp4a_lane_s;
        input [31:0] la, lb, lacc;
        integer kk;
        reg signed [8:0] pr;
        reg signed [31:0] s;
        begin
            s = $signed(lacc);
            for (kk = 0; kk < 8; kk = kk + 1) begin
                pr = $signed({{5{la[kk*4+3]}}, la[kk*4 +: 4]}) *
                     $signed({{5{lb[kk*4+3]}}, lb[kk*4 +: 4]});
                s = s + {{23{pr[8]}}, pr};
            end
            dp4a_lane_s = s;
        end
    endfunction

    function automatic [127:0] vdp4a_i4;
        input [127:0] a, b, acc;
        integer ll;
        begin
            vdp4a_i4 = 128'b0;
            for (ll = 0; ll < 4; ll = ll + 1)
                vdp4a_i4[ll*32 +: 32] =
                    dp4a_lane_s(a[ll*32 +: 32], b[ll*32 +: 32], acc[ll*32 +: 32]);
        end
    endfunction

    // ---- FP32 stub helpers (4 lanes × 32-bit) ----
    // TODO: replace with Intel alt_fp_add / alt_fp_mult IP at synthesis.
    function automatic [127:0] vadd_f32_stub;
        input [127:0] a, b;
        integer ll;
        begin
            vadd_f32_stub = 128'b0;
            for (ll = 0; ll < 4; ll = ll + 1)
                vadd_f32_stub[ll*32 +: 32] = a[ll*32 +: 32] + b[ll*32 +: 32];
        end
    endfunction

    function automatic [127:0] vmadd_f32_stub;
        input [127:0] a, b, acc;
        integer ll;
        begin
            vmadd_f32_stub = 128'b0;
            for (ll = 0; ll < 4; ll = ll + 1)
                vmadd_f32_stub[ll*32 +: 32] =
                    acc[ll*32 +: 32] + a[ll*32 +: 32];  // placeholder
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            result_reg <= 128'b0;
        end else if (enable && core_state == 3'b101) begin // EXECUTE state
            case (decoded_valu_op)
                // ---- INT8 ops ----
                VALU_VADD_I8:   result_reg <= vadd_i8(vs1, vs2);
                VALU_VMUL_I8:   result_reg <= vmul_i8(vs1, vs2);
                VALU_VMADD_I8:  result_reg <= vmadd_i8(vs1, vs2, vacc);
                // ---- INT4 dot-product accumulate (4 × 8-lane) ----
                VALU_VDP4A_I4:  result_reg <= vdp4a_i4(vs1, vs2, vacc);
                // ---- FP32 stubs (4 lanes) ----
                VALU_VADD_F32:  result_reg <= vadd_f32_stub(vs1, vs2);
                VALU_VMUL_F32:  result_reg <= vs1;        // placeholder
                VALU_VMADD_F32: result_reg <= vmadd_f32_stub(vs1, vs2, vacc);
                // ---- Prefetch hint: pass vs1 (address) through unchanged ----
                VALU_VPREFETCH: result_reg <= vs1;
                default:        result_reg <= 128'b0;
            endcase
        end
    end
endmodule
