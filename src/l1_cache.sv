`default_nettype none
`timescale 1ns/1ns

// L1 DATA CACHE — Phase 5 (2-way set-associative, write-through)
//
// One instance per thread.  Sits transparently between a single LSU and the
// data-memory controller that is shared across all threads in the core.
//
// Parameters
//   SETS      — Number of cache sets.  Must be a power of 2.  (default 16)
//   ADDR_BITS — Width of a word-addressed memory address.     (default 8)
//   DATA_BITS — Width of one data word in bits.               (default 32)
//
// Timing
//   Hit  latency : 1 cycle  (tag look-up is registered; data presented the
//                             cycle after the LSU asserts lsu_read_valid)
//   Miss latency : memory-controller round-trip + 1 fill cycle
//
// Write policy : write-through.  On a store the cache tag array is updated
//   (if the address is already cached) and the write is forwarded to the
//   memory controller unconditionally.  No dirty bits are required.
//
// Interface
//   lsu_*  — connects to the LSU outputs / inputs
//   mem_*  — connects to the data-memory controller channels
//
// The lsu_read_ready / lsu_write_ready outputs mirror the mem_read_ready /
// mem_write_ready handshake that the LSU normally waits on, allowing the
// cache to be inserted transparently without modifying lsu.sv.
module l1_cache #(
    parameter SETS      = 16,
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 32
) (
    input wire clk,
    input wire reset,

    // ---- LSU-side (from one thread's LSU) ----
    input  wire                  lsu_read_valid,
    input  wire [ADDR_BITS-1:0]  lsu_read_address,
    output reg                   lsu_read_ready,
    output reg  [DATA_BITS-1:0]  lsu_read_data,

    input  wire                  lsu_write_valid,
    input  wire [ADDR_BITS-1:0]  lsu_write_address,
    input  wire [DATA_BITS-1:0]  lsu_write_data,
    output reg                   lsu_write_ready,

    // ---- Memory-side (to / from data-memory controller, one channel) ----
    output reg                   mem_read_valid,
    output reg  [ADDR_BITS-1:0]  mem_read_address,
    input  wire                  mem_read_ready,
    input  wire [DATA_BITS-1:0]  mem_read_data,

    output reg                   mem_write_valid,
    output reg  [ADDR_BITS-1:0]  mem_write_address,
    output reg  [DATA_BITS-1:0]  mem_write_data,
    input  wire                  mem_write_ready
);
    // ---- Address decomposition ----
    localparam INDEX_BITS = $clog2(SETS);
    localparam TAG_BITS   = ADDR_BITS - INDEX_BITS;

    // ---- 2-way set-associative storage ----
    // valid[set][way], tag[set][way], data[set][way]
    reg                 valid [SETS-1:0][1:0];
    reg [TAG_BITS-1:0]  tag   [SETS-1:0][1:0];
    reg [DATA_BITS-1:0] data  [SETS-1:0][1:0];
    // LRU bit per set: 0 = way 0 is LRU (evict way 0 next), 1 = way 1 is LRU
    reg                 lru   [SETS-1:0];

    // ---- Internal state machine ----
    localparam S_IDLE    = 2'd0; // Waiting for an LSU request
    localparam S_MEMREQ  = 2'd1; // Read-miss: asserting mem_read_valid
    localparam S_MEMWAIT = 2'd2; // Read-miss: waiting for mem_read_ready
    localparam S_WTWAIT  = 2'd3; // Write-through: waiting for mem_write_ready

    reg [1:0]            state;
    reg [ADDR_BITS-1:0]  pending_addr;
    reg [DATA_BITS-1:0]  pending_wdata;

    // ---- Combinatorial hit detection (read) ----
    wire [INDEX_BITS-1:0] r_idx = lsu_read_address[INDEX_BITS-1:0];
    wire [TAG_BITS-1:0]   r_tag = lsu_read_address[ADDR_BITS-1:INDEX_BITS];
    wire r_hit0 = valid[r_idx][0] && (tag[r_idx][0] == r_tag);
    wire r_hit1 = valid[r_idx][1] && (tag[r_idx][1] == r_tag);
    wire r_hit  = r_hit0 || r_hit1;

    // ---- Combinatorial hit detection (write) ----
    wire [INDEX_BITS-1:0] w_idx = lsu_write_address[INDEX_BITS-1:0];
    wire [TAG_BITS-1:0]   w_tag = lsu_write_address[ADDR_BITS-1:INDEX_BITS];
    wire w_hit0 = valid[w_idx][0] && (tag[w_idx][0] == w_tag);
    wire w_hit1 = valid[w_idx][1] && (tag[w_idx][1] == w_tag);

    integer ki;

    always @(posedge clk) begin
        if (reset) begin
            state           <= S_IDLE;
            lsu_read_ready  <= 1'b0;
            lsu_write_ready <= 1'b0;
            mem_read_valid  <= 1'b0;
            mem_write_valid <= 1'b0;
            pending_addr    <= {ADDR_BITS{1'b0}};
            pending_wdata   <= {DATA_BITS{1'b0}};
            for (ki = 0; ki < SETS; ki = ki + 1) begin
                valid[ki][0] <= 1'b0;
                valid[ki][1] <= 1'b0;
                lru[ki]      <= 1'b0;
            end
        end else begin
            // Default de-assert strobes each cycle
            lsu_read_ready  <= 1'b0;
            lsu_write_ready <= 1'b0;
            mem_read_valid  <= 1'b0;
            mem_write_valid <= 1'b0;

            case (state)
                // ----------------------------------------------------------
                S_IDLE: begin
                    if (lsu_read_valid) begin
                        if (r_hit) begin
                            // ---- Cache hit: return data this cycle ----
                            lsu_read_data  <= r_hit0 ? data[r_idx][0]
                                                     : data[r_idx][1];
                            lsu_read_ready <= 1'b1;
                            // Mark used way as MRU (other way is now LRU)
                            lru[r_idx]     <= r_hit0 ? 1'b1 : 1'b0;
                        end else begin
                            // ---- Cache miss: fetch from memory ----
                            pending_addr <= lsu_read_address;
                            state        <= S_MEMREQ;
                        end
                    end else if (lsu_write_valid) begin
                        // ---- Write-through: update cache if present ----
                        if (w_hit0)
                            data[w_idx][0] <= lsu_write_data;
                        else if (w_hit1)
                            data[w_idx][1] <= lsu_write_data;
                        // Forward write to backing memory
                        pending_addr  <= lsu_write_address;
                        pending_wdata <= lsu_write_data;
                        state         <= S_WTWAIT;
                    end
                end

                // ----------------------------------------------------------
                S_MEMREQ: begin
                    // Issue read to memory controller
                    mem_read_valid   <= 1'b1;
                    mem_read_address <= pending_addr;
                    state            <= S_MEMWAIT;
                end

                // ----------------------------------------------------------
                S_MEMWAIT: begin
                    // Hold the request asserted until memory responds
                    mem_read_valid   <= 1'b1;
                    mem_read_address <= pending_addr;
                    if (mem_read_ready) begin
                        mem_read_valid <= 1'b0;
                        // ---- Fill cache: evict the LRU way ----
                        begin
                            reg [INDEX_BITS-1:0] f_idx;
                            reg [TAG_BITS-1:0]   f_tag;
                            reg                  fill_way;
                            f_idx    = pending_addr[INDEX_BITS-1:0];
                            f_tag    = pending_addr[ADDR_BITS-1:INDEX_BITS];
                            fill_way = lru[f_idx];
                            valid[f_idx][fill_way] <= 1'b1;
                            tag  [f_idx][fill_way] <= f_tag;
                            data [f_idx][fill_way] <= mem_read_data;
                            // Filled way is now MRU
                            lru[f_idx] <= ~fill_way;
                        end
                        // Return fetched data to LSU
                        lsu_read_data  <= mem_read_data;
                        lsu_read_ready <= 1'b1;
                        state          <= S_IDLE;
                    end
                end

                // ----------------------------------------------------------
                S_WTWAIT: begin
                    // Hold write request until memory controller acknowledges
                    mem_write_valid   <= 1'b1;
                    mem_write_address <= pending_addr;
                    mem_write_data    <= pending_wdata;
                    if (mem_write_ready) begin
                        mem_write_valid <= 1'b0;
                        lsu_write_ready <= 1'b1;
                        state           <= S_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
