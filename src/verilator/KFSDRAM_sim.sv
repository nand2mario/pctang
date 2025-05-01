//
// KFSDRAM Verilog Simulation Model
//
// nand2mario, April 2025
//
module KFSDRAM #(
    parameter sdram_col_width       = 9,
    parameter sdram_row_width       = 13,
    parameter sdram_bank_width      = 2,
    parameter sdram_data_width      = 16,
    parameter sdram_no_refresh      = 1'b0,
    parameter sdram_trc             = 16'd5-16'd1,
    parameter sdram_trp             = 16'd1-16'd1,
    parameter sdram_tmrd            = 16'd2-16'd1,
    parameter sdram_trcd            = 16'd1-16'd1,
    parameter sdram_tdpl            = 16'd2-16'd1,
    parameter cas_latency           = 3'b010,
    parameter sdram_init_wait       = 16'd10000,
    parameter sdram_refresh_cycle   = 16'd00100,
    parameter sdram_force_refresh   = 16'd00400
) (
    input   logic                               sdram_clock,
    input   logic                               sdram_reset,

    // Control
    input   logic   [sdram_col_width
                    + sdram_row_width
                    + sdram_bank_width-1:0]     address,
    input   logic   [sdram_col_width-1:0]       access_num,
    input   logic   [sdram_data_width-1:0]      data_in,
    output  reg     [sdram_data_width-1:0]      data_out,
    input   logic                               write_request,
    input   logic                               read_request,   
    input   logic                               enable_refresh,
    output  reg                                 write_flag,  // write operation is complete
    output  reg                                 read_flag,   // data is ready on data_out
    output  logic                               refresh_mode,
    output  logic                               idle,

    // SDRAM
    output  logic   [sdram_row_width-1:0]       sdram_address,
    output  logic                               sdram_cke,
    output  logic                               sdram_cs,
    output  logic                               sdram_ras,
    output  logic                               sdram_cas,
    output  logic                               sdram_we,
    output  logic   [sdram_bank_width-1:0]      sdram_ba,
    input   logic   [sdram_data_width-1:0]      sdram_dq_in,
    output  logic   [sdram_data_width-1:0]      sdram_dq_out,
    output  logic                               sdram_dq_io
);

reg [15:0] mem [0:16*1024*1024-1];  // 32MB of memory
reg [2:0] cycle;
reg busy_buf = 1;
// assign busy = busy_buf;

reg [3:0] start_cnt = 15;
reg [2:0] state;
localparam IDLE = 0;
localparam RAS = 1;
localparam CAS0 = 2;
localparam CAS1 = 3;
// localparam READY = 4;

assign idle = state == IDLE;

reg [24:1] addr;
reg [15:0] din;
reg wr;
reg [1:0] be;


always @(posedge sdram_clock) begin
    start_cnt <= start_cnt == 0 ? 0 : start_cnt - 1;
    if (start_cnt == 1)
        busy_buf <= 0;

    read_flag <= 0;
    write_flag <= 0;

    case (state)
    IDLE: begin
        if (write_request | read_request) begin
            addr <= address;
            din <= data_in;
            wr <= write_request;
            be <= 2'b11;
            busy_buf <= 1;
            state <= RAS;
        end 
    end

    RAS: state <= CAS0;

    CAS0: state <= CAS1;

    CAS1: begin
        if (wr) begin
            mem[addr] <= din;
            write_flag <= 1;
            // $display("sdram[%h]<=%h", addr, din);
        end else begin
            data_out <= mem[addr];
            read_flag <= 1;
            // $display("sdram[%h] = %h", addr, mem[addr]);
        end
        state <= IDLE;
    end

    default: ;

    endcase

end

endmodule
