`default_nettype none
`timescale 1ns/1ns

// LOAD-STORE UNIT (parametric data bus, byte/halfword/word/quad-word — Phase 1/7c)
// Handles asynchronous memory load and store operations.
// Supports LB/LBU, LH/LHU, LW (scalar loads) and SB, SH, SW (scalar stores).
// Phase 7c extension: quad-word (128-bit) load / store when decoded_mem_size == 2'b11.
//   VLW.Q  — LOAD opcode  with funct3 = 3'b011 (decoded_mem_size = 2'b11)
//   VSW.Q  — STORE opcode with funct3 = 3'b011 (decoded_mem_size = 2'b11)
// Each thread in each core has its own LSU.
module lsu #(
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 32  // Set to 128 by core.sv when VECTOR_ENABLE=1
) (
    input wire clk,
    input wire reset,
    input wire enable,

    input reg [2:0] core_state,

    input reg decoded_mem_read_enable,
    input reg decoded_mem_write_enable,
    input reg [1:0] decoded_mem_size,       // 0=byte 1=halfword 2=word 3=quad-word(128b)
    input reg decoded_mem_sign_extend,

    // Effective address = rs1 (pre-computed by ALU); scalar store data = rs2
    input reg [31:0] rs1,
    input reg [31:0] rs2,
    // Phase 7c: vector store source and vector load destination
    input reg  [127:0] vrs2,    // 128-bit store data (from vreg.sv)
    output reg [127:0] lsu_vout, // 128-bit load result (to vreg.sv)

    // Data memory interface (bus width = DATA_MEM_DATA_BITS)
    output reg                            mem_read_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0]   mem_read_address,
    input  reg                            mem_read_ready,
    input  reg [DATA_MEM_DATA_BITS-1:0]   mem_read_data,

    output reg                            mem_write_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0]   mem_write_address,
    output reg [DATA_MEM_DATA_BITS-1:0]   mem_write_data,
    input  reg                            mem_write_ready,

    output reg [1:0]  lsu_state,
    output reg [31:0] lsu_out      // Scalar load result (to scalar registers)
);
    localparam IDLE       = 2'b00;
    localparam REQUESTING = 2'b01;
    localparam WAITING    = 2'b10;
    localparam DONE       = 2'b11;

    always @(posedge clk) begin
        if (reset) begin
            lsu_state         <= IDLE;
            lsu_out           <= 32'b0;
            lsu_vout          <= 128'b0;
            mem_read_valid    <= 1'b0;
            mem_read_address  <= {DATA_MEM_ADDR_BITS{1'b0}};
            mem_write_valid   <= 1'b0;
            mem_write_address <= {DATA_MEM_ADDR_BITS{1'b0}};
            mem_write_data    <= {DATA_MEM_DATA_BITS{1'b0}};
        end else if (enable) begin
            // ---- Load (LB / LBU / LH / LHU / LW / VLW.Q) ----
            if (decoded_mem_read_enable) begin
                case (lsu_state)
                    IDLE: begin
                        if (core_state == 3'b011) // REQUEST state
                            lsu_state <= REQUESTING;
                    end
                    REQUESTING: begin
                        mem_read_valid   <= 1'b1;
                        mem_read_address <= rs1[DATA_MEM_ADDR_BITS-1:0]; // word-addressed
                        lsu_state        <= WAITING;
                    end
                    WAITING: begin
                        if (mem_read_ready) begin
                            mem_read_valid <= 1'b0;
                            // Sign/zero extend based on access size
                            case (decoded_mem_size)
                                2'b00: lsu_out <= decoded_mem_sign_extend
                                    ? {{24{mem_read_data[7]}},  mem_read_data[7:0]}
                                    : {24'b0, mem_read_data[7:0]};
                                2'b01: lsu_out <= decoded_mem_sign_extend
                                    ? {{16{mem_read_data[15]}}, mem_read_data[15:0]}
                                    : {16'b0, mem_read_data[15:0]};
                                // Phase 7c: quad-word load → capture full data bus
                                2'b11: lsu_vout <= mem_read_data[127:0];
                                default: lsu_out <= mem_read_data[31:0]; // word
                            endcase
                            lsu_state <= DONE;
                        end
                    end
                    DONE: begin
                        if (core_state == 3'b110) // UPDATE state
                            lsu_state <= IDLE;
                    end
                endcase
            end

            // ---- Store (SB / SH / SW / VSW.Q) ----
            if (decoded_mem_write_enable) begin
                case (lsu_state)
                    IDLE: begin
                        if (core_state == 3'b011)
                            lsu_state <= REQUESTING;
                    end
                    REQUESTING: begin
                        mem_write_valid   <= 1'b1;
                        mem_write_address <= rs1[DATA_MEM_ADDR_BITS-1:0];
                        case (decoded_mem_size)
                            2'b00: mem_write_data <= {{(DATA_MEM_DATA_BITS-8){1'b0}},   rs2[7:0]};
                            2'b01: mem_write_data <= {{(DATA_MEM_DATA_BITS-16){1'b0}},  rs2[15:0]};
                            // Phase 7c: quad-word store from vector register
                            2'b11: mem_write_data <= vrs2[DATA_MEM_DATA_BITS-1:0];
                            default: mem_write_data <= {{(DATA_MEM_DATA_BITS-32){1'b0}}, rs2}; // word
                        endcase
                        lsu_state <= WAITING;
                    end
                    WAITING: begin
                        if (mem_write_ready) begin
                            mem_write_valid <= 1'b0;
                            lsu_state       <= DONE;
                        end
                    end
                    DONE: begin
                        if (core_state == 3'b110)
                            lsu_state <= IDLE;
                    end
                endcase
            end
        end
    end
endmodule
