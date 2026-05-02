`default_nettype none
`timescale 1ns/1ns

// RASTERIZER — Phase 6 (Scan-line tile rasterizer with barycentric interpolation)
// Converts a triangle primitive into a stream of covered fragments (pixels).
// One triangle is submitted per transaction; the module streams out one
// fragment record per covered pixel until the bounding box is exhausted.
//
// Coordinate convention:
//   All vertex inputs are 32-bit signed fixed-point with 16 integer + 16
//   fractional bits (16.16 format).  Pixel centres are at (.5, .5) offsets
//   inside each integer grid cell.
//
// Fragment output includes barycentric weights so the shader can interpolate
// vertex attributes (colour, texture coordinates, depth).
//
// A production implementation would add:
//   • Tile-based coarse / fine raster (hierarchical coverage tests)
//   • Early-Z / Hi-Z depth culling
//   • Multi-sample anti-aliasing (MSAA)
//   • Sub-pixel precision guard bands
//   • Back-face / view-frustum culling
module rasterizer #(
    parameter SCREEN_W  = 640,
    parameter SCREEN_H  = 480,
    parameter COORD_BITS = 32   // 16.16 fixed-point
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // ---- Triangle input ----
    input  wire        tri_valid,
    // Vertex positions in 16.16 fixed-point screen space
    input  wire signed [COORD_BITS-1:0] v0_x, v0_y,
    input  wire signed [COORD_BITS-1:0] v1_x, v1_y,
    input  wire signed [COORD_BITS-1:0] v2_x, v2_y,
    output wire        tri_ready,       // High when idle and ready for new triangle

    // ---- Fragment output ----
    output reg         frag_valid,
    output reg  [15:0] frag_x,
    output reg  [15:0] frag_y,
    // Barycentric weights (16.16, unnormalised — divide by the triangle area
    // to obtain normalised weights for attribute interpolation)
    output reg  signed [COORD_BITS-1:0] frag_w0,
    output reg  signed [COORD_BITS-1:0] frag_w1,
    output reg  signed [COORD_BITS-1:0] frag_w2,
    input  wire        frag_ready       // Back-pressure from fragment shader
);
    localparam S_IDLE  = 2'd0,
               S_SETUP = 2'd1,
               S_SCAN  = 2'd2,
               S_EMIT  = 2'd3;

    reg [1:0] state;
    reg [15:0] cur_x, cur_y;
    reg [15:0] bbox_x0, bbox_y0, bbox_x1, bbox_y1;

    // ---- 2-D edge function: e(p) = (b-a)×(p-a) ----
    // Returns positive when p is on the left of edge a→b (counter-clockwise winding).
    function automatic signed [COORD_BITS-1:0] edge_fn;
        input signed [COORD_BITS-1:0] ax, ay, bx, by, px, py;
        begin
            edge_fn = (bx - ax) * (py - ay) - (by - ay) * (px - ax);
        end
    endfunction

    // Latch vertex coordinates during SETUP so we can reference them in SCAN
    reg signed [COORD_BITS-1:0] lv0_x, lv0_y, lv1_x, lv1_y, lv2_x, lv2_y;

    assign tri_ready = (state == S_IDLE);

    // ---- Clamped minimum / maximum helpers ----
    function automatic [15:0] smax16;
        input signed [15:0] a; input signed [15:0] b;
        smax16 = ($signed(a) > $signed(b)) ? a : b;
    endfunction
    function automatic [15:0] smin16;
        input signed [15:0] a; input signed [15:0] b;
        smin16 = ($signed(a) < $signed(b)) ? a : b;
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            state      <= S_IDLE;
            frag_valid <= 1'b0;
            cur_x      <= 16'b0;
            cur_y      <= 16'b0;
        end else if (enable) begin
            frag_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (tri_valid) begin
                        lv0_x <= v0_x; lv0_y <= v0_y;
                        lv1_x <= v1_x; lv1_y <= v1_y;
                        lv2_x <= v2_x; lv2_y <= v2_y;
                        state <= S_SETUP;
                    end
                end

                S_SETUP: begin
                    // Compute axis-aligned bounding box in integer pixel space
                    // using the integer (upper 16-bit) parts of each vertex.
                    begin
                        reg [15:0] x0, x1, y0, y1;
                        // Integer parts
                        x0 = smin16(lv0_x[31:16], smin16(lv1_x[31:16], lv2_x[31:16]));
                        y0 = smin16(lv0_y[31:16], smin16(lv1_y[31:16], lv2_y[31:16]));
                        x1 = smax16(lv0_x[31:16], smax16(lv1_x[31:16], lv2_x[31:16]));
                        y1 = smax16(lv0_y[31:16], smax16(lv1_y[31:16], lv2_y[31:16]));
                        // Clamp to screen
                        bbox_x0 <= (x0 < 16'd0)           ? 16'd0           : x0;
                        bbox_y0 <= (y0 < 16'd0)           ? 16'd0           : y0;
                        bbox_x1 <= (x1 >= SCREEN_W[15:0]) ? SCREEN_W - 1    : x1;
                        bbox_y1 <= (y1 >= SCREEN_H[15:0]) ? SCREEN_H - 1    : y1;
                    end
                    state <= S_SCAN;
                end

                S_SCAN: begin
                    begin
                        // Pixel centre offset: (cur_x + 0.5, cur_y + 0.5) in 16.16
                        automatic signed [COORD_BITS-1:0] px, py;
                        automatic signed [COORD_BITS-1:0] w0, w1, w2;
                        px = {16'(cur_x), 16'h8000};
                        py = {16'(cur_y), 16'h8000};
                        w0 = edge_fn(lv1_x, lv1_y, lv2_x, lv2_y, px, py);
                        w1 = edge_fn(lv2_x, lv2_y, lv0_x, lv0_y, px, py);
                        w2 = edge_fn(lv0_x, lv0_y, lv1_x, lv1_y, px, py);

                        if (w0 >= 0 && w1 >= 0 && w2 >= 0) begin
                            // Pixel is inside the triangle
                            frag_w0 <= w0;
                            frag_w1 <= w1;
                            frag_w2 <= w2;
                            frag_x  <= cur_x;
                            frag_y  <= cur_y;
                            state   <= S_EMIT;
                        end else begin
                            // Advance to next pixel; wrap row at bbox boundary
                            if (cur_x < bbox_x1) begin
                                cur_x <= cur_x + 1;
                            end else begin
                                cur_x <= bbox_x0;
                                if (cur_y < bbox_y1)
                                    cur_y <= cur_y + 1;
                                else
                                    state <= S_IDLE; // triangle exhausted
                            end
                        end
                    end
                end

                S_EMIT: begin
                    if (frag_ready) begin
                        frag_valid <= 1'b1;
                        // Advance scan position
                        if (cur_x < bbox_x1) begin
                            cur_x <= cur_x + 1;
                            state <= S_SCAN;
                        end else begin
                            cur_x <= bbox_x0;
                            if (cur_y < bbox_y1) begin
                                cur_y <= cur_y + 1;
                                state <= S_SCAN;
                            end else begin
                                state <= S_IDLE;
                            end
                        end
                    end
                end
            endcase
        end
    end
endmodule
