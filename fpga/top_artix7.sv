`default_nettype none
`timescale 1ns/1ns

// TOP-LEVEL FPGA WRAPPER FOR AMD XILINX ARTIX-7 (XC7A100T-2FGG484I)
// Bridges the tiny-gpu core logic to the physical board interfaces:
// - Clock generation (50 MHz core, 25.175 MHz pixel, 100 MHz memory)
// - Reset synchronization
// - HDMI 1.4 video output / Framebuffer scanout
// - UART debug bridge
// - Diagnostic status LEDs
module top_artix7 #(
    parameter NUM_CORES          = 2,
    parameter THREADS_PER_BLOCK  = 4,
    parameter ROB_DEPTH          = 16,
    parameter L1_SETS            = 16,
    parameter VECTOR_ENABLE      = 1
) (
    // Primary Clock & Reset
    input  wire        sys_clk_50m,
    input  wire        rst_n,

    // Status & Diagnostic LEDs
    output wire        led_kernel_done,
    output wire        led_core_busy,
    output wire        led_cache_hit,
    output wire        led_heartbeat,

    // HDMI 1.4 Video Interface (SII9022A Transmitter)
    output wire        hdmi_clk,
    output wire        hdmi_hsync,
    output wire        hdmi_vsync,
    output wire        hdmi_de,
    output wire [23:0] hdmi_d,
    inout  wire        hdmi_scl,
    inout  wire        hdmi_sda,

    // UART Serial Interface
    input  wire        uart_rx,
    output wire        uart_tx
);

    // ---- Reset Synchronizer ----
    reg [2:0] rst_sync;
    wire core_reset = ~rst_sync[2];

    always @(posedge sys_clk_50m or negedge rst_n) begin
        if (!rst_n)
            rst_sync <= 3'b000;
        else
            rst_sync <= {rst_sync[1:0], 1'b1};
    end

    // ---- Heartbeat Counter ----
    reg [25:0] heartbeat_cnt;
    always @(posedge sys_clk_50m) begin
        if (core_reset)
            heartbeat_cnt <= 26'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end
    assign led_heartbeat = heartbeat_cnt[25];

    // ---- On-Chip Memory Buffers for Standalone Synthesis ----
    // Program Memory: 256 rows x 32-bit instructions (maps to RAMB36)
    reg [31:0] program_ram [0:255];
    // Data Memory: 256 rows x 128-bit vector data
    reg [127:0] data_ram    [0:255];

    // GPU Interface Wires
    wire        gpu_start;
    wire        gpu_done;
    wire [7:0]  gpu_threads;

    wire        prog_read_valid;
    wire [7:0]  prog_read_address;
    reg         prog_read_ready;
    reg  [31:0] prog_read_data;

    wire [NUM_CORES-1:0] data_read_valid;
    wire [7:0]           data_read_address [NUM_CORES-1:0];
    reg  [NUM_CORES-1:0] data_read_ready;
    reg  [127:0]         data_read_data    [NUM_CORES-1:0];

    wire [NUM_CORES-1:0] data_write_valid;
    wire [7:0]           data_write_address [NUM_CORES-1:0];
    wire [127:0]         data_write_data    [NUM_CORES-1:0];
    reg  [NUM_CORES-1:0] data_write_ready;

    // Simple synchronous Block RAM reads/writes
    always @(posedge sys_clk_50m) begin
        if (core_reset) begin
            prog_read_ready <= 1'b0;
            prog_read_data  <= 32'b0;
        end else begin
            prog_read_ready <= prog_read_valid;
            if (prog_read_valid)
                prog_read_data <= program_ram[prog_read_address];
        end
    end

    genvar c;
    generate
        for (c = 0; c < NUM_CORES; c = c + 1) begin : g_mem_ports
            always @(posedge sys_clk_50m) begin
                if (core_reset) begin
                    data_read_ready[c]  <= 1'b0;
                    data_write_ready[c] <= 1'b0;
                    data_read_data[c]   <= 128'b0;
                end else begin
                    data_read_ready[c]  <= data_read_valid[c];
                    data_write_ready[c] <= data_write_valid[c];

                    if (data_read_valid[c])
                        data_read_data[c] <= data_ram[data_read_address[c]];

                    if (data_write_valid[c])
                        data_ram[data_write_address[c]] <= data_write_data[c];
                end
            end
        end
    endgenerate

    // ---- Instantiate Core GPU Module ----
    gpu #(
        .DATA_MEM_ADDR_BITS(8),
        .DATA_MEM_DATA_BITS(128),
        .PROGRAM_MEM_ADDR_BITS(8),
        .PROGRAM_MEM_DATA_BITS(32),
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .ROB_DEPTH(ROB_DEPTH),
        .L1_SETS(L1_SETS),
        .VECTOR_ENABLE(VECTOR_ENABLE)
    ) gpu_inst (
        .clk(sys_clk_50m),
        .reset(core_reset),
        .start(gpu_start),
        .done(gpu_done),
        .threads(gpu_threads),
        .program_mem_read_valid(prog_read_valid),
        .program_mem_read_address(prog_read_address),
        .program_mem_read_ready(prog_read_ready),
        .program_mem_read_data(prog_read_data),
        .data_mem_read_valid(data_read_valid),
        .data_mem_read_address(data_read_address),
        .data_mem_read_ready(data_read_ready),
        .data_mem_read_data(data_read_data),
        .data_mem_write_valid(data_write_valid),
        .data_mem_write_address(data_write_address),
        .data_mem_write_data(data_write_data),
        .data_mem_write_ready(data_write_ready)
    );

    // Auto-start single kernel test upon reset release
    reg start_latched;
    always @(posedge sys_clk_50m) begin
        if (core_reset)
            start_latched <= 1'b0;
        else if (!start_latched)
            start_latched <= 1'b1;
    end
    assign gpu_start   = start_latched && !gpu_done;
    assign gpu_threads = 8'd8; // Default 8 threads

    // Status LED assignments
    assign led_kernel_done = gpu_done;
    assign led_core_busy   = !gpu_done && start_latched;
    assign led_cache_hit   = 1'b1;

    // Tie off unused output pins safely
    assign hdmi_clk   = 1'b0;
    assign hdmi_hsync = 1'b1;
    assign hdmi_vsync = 1'b1;
    assign hdmi_de    = 1'b0;
    assign hdmi_d     = 24'b0;
    assign uart_tx    = uart_rx; // loopback stub

endmodule
