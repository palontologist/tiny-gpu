`default_nettype none
`timescale 1ns/1ns

// TEXTURE UNIT — Phase 6 (Bilinear Interpolation, INT8 texels)
// Samples a 2-D texture using bilinear filtering.
// Inputs are 8.8 fixed-point UV coordinates; the texture is stored as
// packed INT8 values in a flat memory array (single-channel greyscale stub).
// A production implementation would:
//   • Add 4-channel RGBA support
//   • Instantiate an Intel M20K-backed texture cache
//   • Pipeline the 4 texel fetches to hide memory latency
//   • Support mipmaps and anisotropic filtering
//
// On Intel FPGAs the texture memory should be an altsyncram M20K instance;
// replace the generic 'reg [7:0] tex_mem' below with the appropriate IP.
module texture_unit #(
    parameter TEX_ADDR_BITS = 12  // Addressable texel range (4096 entries)
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Sample request
    input  wire        sample_valid,
    input  wire [15:0] tex_u,              // 8.8 fixed-point U  (integer.fraction)
    input  wire [15:0] tex_v,              // 8.8 fixed-point V
    input  wire [TEX_ADDR_BITS-1:0] tex_base_addr,
    input  wire [7:0]  tex_width,          // Texture width in texels

    // Texture memory interface (single read port)
    output reg                      tex_mem_read_valid,
    output reg [TEX_ADDR_BITS-1:0]  tex_mem_read_address,
    input  reg                      tex_mem_read_ready,
    input  reg [7:0]                tex_mem_read_data,

    // Result
    output reg        sample_ready,
    output reg [7:0]  sample_r,
    output reg [7:0]  sample_g,
    output reg [7:0]  sample_b,
    output reg [7:0]  sample_a
);
    // State machine: fetch 4 neighbouring texels then blend
    localparam S_IDLE    = 3'd0,
               S_FETCH00 = 3'd1,  // texel (u,   v  )
               S_FETCH01 = 3'd2,  // texel (u+1, v  )
               S_FETCH10 = 3'd3,  // texel (u,   v+1)
               S_FETCH11 = 3'd4,  // texel (u+1, v+1)
               S_BLEND   = 3'd5,
               S_DONE    = 3'd6;

    reg [2:0] state;
    reg [7:0] p00, p01, p10, p11;  // four sampled texels
    reg [7:0] frac_u, frac_v;      // fractional parts (8-bit, 0..255)
    reg [7:0] iu, iv;              // integer parts

    always @(posedge clk) begin
        if (reset) begin
            state              <= S_IDLE;
            sample_ready       <= 1'b0;
            tex_mem_read_valid <= 1'b0;
            sample_r <= 8'b0; sample_g <= 8'b0;
            sample_b <= 8'b0; sample_a <= 8'hFF;
        end else if (enable) begin
            sample_ready <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (sample_valid) begin
                        iu     <= tex_u[15:8];
                        iv     <= tex_v[15:8];
                        frac_u <= tex_u[7:0];
                        frac_v <= tex_v[7:0];
                        state  <= S_FETCH00;
                    end
                end

                S_FETCH00: begin
                    tex_mem_read_valid   <= 1'b1;
                    tex_mem_read_address <= tex_base_addr
                                         + {4'b0, iv} * {4'b0, tex_width}
                                         + {4'b0, iu};
                    if (tex_mem_read_ready) begin
                        tex_mem_read_valid <= 1'b0;
                        p00   <= tex_mem_read_data;
                        state <= S_FETCH01;
                    end
                end

                S_FETCH01: begin
                    tex_mem_read_valid   <= 1'b1;
                    tex_mem_read_address <= tex_base_addr
                                         + {4'b0, iv} * {4'b0, tex_width}
                                         + {4'b0, iu} + 1;
                    if (tex_mem_read_ready) begin
                        tex_mem_read_valid <= 1'b0;
                        p01   <= tex_mem_read_data;
                        state <= S_FETCH10;
                    end
                end

                S_FETCH10: begin
                    tex_mem_read_valid   <= 1'b1;
                    tex_mem_read_address <= tex_base_addr
                                         + ({4'b0, iv} + 1) * {4'b0, tex_width}
                                         + {4'b0, iu};
                    if (tex_mem_read_ready) begin
                        tex_mem_read_valid <= 1'b0;
                        p10   <= tex_mem_read_data;
                        state <= S_FETCH11;
                    end
                end

                S_FETCH11: begin
                    tex_mem_read_valid   <= 1'b1;
                    tex_mem_read_address <= tex_base_addr
                                         + ({4'b0, iv} + 1) * {4'b0, tex_width}
                                         + {4'b0, iu} + 1;
                    if (tex_mem_read_ready) begin
                        tex_mem_read_valid <= 1'b0;
                        p11   <= tex_mem_read_data;
                        state <= S_BLEND;
                    end
                end

                S_BLEND: begin
                    // Bilinear blend using 8-bit fixed-point fractions (0..255 ≡ 0..1)
                    //   top  = lerp(p00, p01, frac_u)
                    //   bot  = lerp(p10, p11, frac_u)
                    //   out  = lerp(top, bot, frac_v)
                    reg [15:0] top, bot, blend;
                    top   = (16'(p00) * (16'd255 - 16'(frac_u))
                           + 16'(p01) *             16'(frac_u)) >> 8;
                    bot   = (16'(p10) * (16'd255 - 16'(frac_u))
                           + 16'(p11) *             16'(frac_u)) >> 8;
                    blend = (top      * (16'd255 - 16'(frac_v))
                           + bot      *             16'(frac_v)) >> 8;
                    // Greyscale stub: replicate across all channels
                    sample_r <= blend[7:0];
                    sample_g <= blend[7:0];
                    sample_b <= blend[7:0];
                    sample_a <= 8'hFF;
                    state    <= S_DONE;
                end

                S_DONE: begin
                    sample_ready <= 1'b1;
                    state        <= S_IDLE;
                end
            endcase
        end
    end
endmodule
