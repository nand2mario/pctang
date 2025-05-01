//
// PCXT RAM
//
// nand2mario: rewritten using our sdram.v
// April 2025
//
module RAM (
    input   logic           clock,
    input   logic           reset,
    input   logic           enable_sdram,
    output  logic           initilized_sdram,
    // I/O Ports
    input   logic   [19:0]  address,
    input   logic   [7:0]   internal_data_bus,      // data input 
    output  logic   [7:0]   data_bus_out,           // data output
    input   logic           memory_read_n,          // read request
    input   logic           memory_write_n,         // write request
    input   logic           no_command_state,       
    output  logic           memory_access_ready,
    output  logic           ram_address_select_n,
    // SDRAM
    output  logic   [12:0]  sdram_address,
    output  logic           sdram_cke,
    output  logic           sdram_cs,
    output  logic           sdram_ras,
    output  logic           sdram_cas,
    output  logic           sdram_we,
    output  logic   [1:0]   sdram_ba,
    input   logic   [15:0]  sdram_dq_in,
    output  logic   [15:0]  sdram_dq_out,
    output  logic           sdram_dq_io,
    output  logic           sdram_ldqm,
    output  logic           sdram_udqm,
    // EMS
    input   logic   [6:0]   map_ems[0:3],           // for ISA expanded memory, not implemented
    input   logic           ems_b1,
    input   logic           ems_b2,
    input   logic           ems_b3,
    input   logic           ems_b4,
    // BIOS
    input  logic    [1:0]  bios_protect_flag,       // [1]: protect F0000h-FFFFFh, [0]: protect EC000h-EFFFFh
    input  logic           tandy_bios_flag,         // not implented
    // Optional flags
    input  logic           enable_a000h,            // not implemnted
    // Wait mode
    input   logic           wait_count_clk_en,      // not implemnted
    input   logic   [1:0]   ram_read_wait_cycle,    // not implemnted
    input   logic   [1:0]   ram_write_wait_cycle    // not implemnted
);

// Memory map
// 0x000000 - 0x09ffff: main memory       (640KB)
// 0x0a0000 - 0x0affff: optional a0000h   (64KB), enabled by enable_a000h
// 0x0b0000 - 0x0bffff: VRAM              (64KB)
// 0x0c0000 - 0x0dffff: reserved          (128KB)
// 0x0f0000 - 0x0fffff: BIOS              (64KB)

assign ram_address_select_n = ~(enable_sdram && ~(address[19:16] == 4'b1011) &&  // B0000h reserved for VRAM
                              ~(~enable_a000h && address[19:16] == 4'b1010));    // A0000h is optional

assign memory_access_ready = ~busy;

wire write_protect = bios_protect_flag[1] & (address[19:16] == 4'b1111)
                     | bios_protect_flag[0] & (address[19:14] == 6'b111011);

reg memory_write_n_delayed;          // FIXME: the first cycle has bad internal_data_bus, so we delay the write command

wire write_command = ~ram_address_select_n & ~memory_write_n_delayed & ~write_protect;
wire read_command = ~ram_address_select_n & ~memory_read_n;

reg write_command_reg, read_command_reg;
reg req_reg, wr_reg;
reg req;
reg wr;
wire ack, busy;

always @(posedge clock) begin
    memory_write_n_delayed <=memory_write_n;
    write_command_reg <= write_command;
    read_command_reg <= read_command;
    req_reg <= req;
    wr_reg <= wr;
end

always @(*) begin
    if (~write_command_reg & write_command) begin          // new write command
        req = ~req_reg;
        wr = 1'b1;
    end else if (~read_command_reg & read_command) begin   // new read command
        req = ~req_reg;
        wr = 1'b0;
    end else begin
        req = req_reg;
        wr = wr_reg;
    end
end

sdram u_sdram (
    .clk(clock),
    .resetn(~reset),
    .refresh_allowed(1'b1),     // refresh takes at most 5 cycles, so it's ok to always allow
    .busy(busy),

    .req0(req),
    .ack0(ack),
    .wr0(wr),
    .addr0(address),
    .din0(internal_data_bus),   // sdram module buffers din at req time
    .dout0(data_bus_out),
    .be0(2'b11),

    .SDRAM_DQ_in(sdram_dq_in),
    .SDRAM_DQ_out(sdram_dq_out),
    .SDRAM_DQ_oen(sdram_dq_io),
    .SDRAM_A(sdram_address),
    .SDRAM_DQM({sdram_udqm, sdram_ldqm}),
    .SDRAM_BA(sdram_ba),
    .SDRAM_nWE(sdram_we),
    .SDRAM_nRAS(sdram_ras),
    .SDRAM_nCAS(sdram_cas),
    .SDRAM_nCS(sdram_cs),
    .SDRAM_CKE(sdram_cke)
);

// set initialized_sdram
always_ff @(posedge clock) begin
    if (reset)
        initilized_sdram <= 1'b0;
    else if (~busy)
        initilized_sdram <= 1'b1;
end

endmodule