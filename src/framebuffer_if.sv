`default_nettype none
`timescale 1ns/1ns

// FRAMEBUFFER INTERFACE — Phase 6
// Bridges the GPU pixel output to a VGA / HDMI display controller.
//
// Design:
//   • Single write port for the fragment shader / rasterizer to deposit pixels
//   • Single read port for the scan-out engine (VGA / HDMI IP)
//   • Simplified H/V sync generation for 640×480 @ 60 Hz (25.175 MHz pixel clock)
//     — in a real design this would be clocked on a separate pixel-clock domain
//     — on Intel FPGAs, instantiate the Intel VIP (alt_vip_*) or HDMI IP via
//       Quartus Platform Designer instead of the sync counters below
//
// Memory model:
//   The framebuffer is modelled as a synchronous single-port RAM.
//   On Intel FPGAs this maps to M20K blocks (altsyncram IP).
//   Replace the 'reg [PIXEL_BITS-1:0] framebuffer' with an altsyncram
//   instantiation for synthesis; keep the model for simulation.
module framebuffer_if #(
    parameter SCREEN_W   = 640,
    parameter SCREEN_H   = 480,
    parameter PIXEL_BITS = 32,       // RGBA8888
    parameter ADDR_BITS  = 19        // ceil(log2(640*480)) = 19
) (
    input wire clk,
    input wire reset,

    // ---- Pixel write port (from fragment shader / rasterizer) ----
    input  wire                   pixel_write_valid,
    input  wire [15:0]            pixel_x,
    input  wire [15:0]            pixel_y,
    input  wire [PIXEL_BITS-1:0]  pixel_data,   // RGBA
    output wire                   pixel_write_ready,

    // ---- Scan-out read port (to HDMI / VGA IP) ----
    input  wire                   scan_read_valid,
    input  wire [ADDR_BITS-1:0]   scan_read_address,
    output reg  [PIXEL_BITS-1:0]  scan_read_data,
    output reg                    scan_read_ready,

    // ---- Display sync (simplified, single-clock) ----
    output reg  hsync,
    output reg  vsync,
    output reg  frame_done,      // Pulses high for one cycle at end of each frame

    // ---- Status ----
    output reg  [ADDR_BITS-1:0]  pixels_written
);
    // ---- Framebuffer RAM (M20K model for simulation) ----
    // On Intel FPGAs replace with:
    //   altsyncram #(.operation_mode("SINGLE_PORT"), .width_a(PIXEL_BITS),
    //                .numwords_a(SCREEN_W*SCREEN_H), .widthad_a(ADDR_BITS), ...)
    //   framebuffer_ram (...);
    reg [PIXEL_BITS-1:0] framebuffer [0:SCREEN_W*SCREEN_H-1];

    wire [ADDR_BITS-1:0] write_addr;
    assign write_addr = pixel_y[8:0] * SCREEN_W[8:0] + pixel_x[9:0];

    // Write port is always ready (no back-pressure in this stub)
    assign pixel_write_ready = 1'b1;

    // ---- VGA timing counters (640×480 @ 60 Hz, 25.175 MHz pixel clock) ----
    // In a real design these counters run on a separate 25.175 MHz clock.
    // Here they share the core clock for simulation convenience.
    localparam H_ACTIVE  = 640;
    localparam H_FP      = 16;   // front porch
    localparam H_SYNC    = 96;   // sync pulse
    localparam H_BP      = 48;   // back porch
    localparam H_TOTAL   = H_ACTIVE + H_FP + H_SYNC + H_BP; // 800

    localparam V_ACTIVE  = 480;
    localparam V_FP      = 10;
    localparam V_SYNC    = 2;
    localparam V_BP      = 33;
    localparam V_TOTAL   = V_ACTIVE + V_FP + V_SYNC + V_BP; // 525

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    always @(posedge clk) begin
        if (reset) begin
            h_cnt          <= 10'b0;
            v_cnt          <= 10'b0;
            hsync          <= 1'b1;
            vsync          <= 1'b1;
            frame_done     <= 1'b0;
            pixels_written <= {ADDR_BITS{1'b0}};
            scan_read_ready <= 1'b0;
        end else begin
            frame_done <= 1'b0;

            // ---- Pixel write ----
            if (pixel_write_valid
                && pixel_x < SCREEN_W[15:0]
                && pixel_y < SCREEN_H[15:0]) begin
                framebuffer[write_addr] <= pixel_data;
                pixels_written          <= pixels_written + 1;
            end

            // ---- Scan-out read (one-cycle latency) ----
            scan_read_ready <= 1'b0;
            if (scan_read_valid) begin
                scan_read_data  <= framebuffer[scan_read_address];
                scan_read_ready <= 1'b1;
            end

            // ---- H/V sync generation ----
            if (h_cnt < H_TOTAL - 1) begin
                h_cnt <= h_cnt + 1;
            end else begin
                h_cnt <= 10'b0;
                if (v_cnt < V_TOTAL - 1) begin
                    v_cnt <= v_cnt + 1;
                end else begin
                    v_cnt      <= 10'b0;
                    frame_done <= 1'b1;
                end
            end

            // Sync polarity: negative (active-low) for 640×480 standard timing
            hsync <= ~((h_cnt >= H_ACTIVE + H_FP)
                    && (h_cnt <  H_ACTIVE + H_FP + H_SYNC));
            vsync <= ~((v_cnt >= V_ACTIVE + V_FP)
                    && (v_cnt <  V_ACTIVE + V_FP + V_SYNC));
        end
    end
endmodule
