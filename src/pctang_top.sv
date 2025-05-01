/*
 * PCXT_MiSTer ported to Tang FPGA
 *
 * nand2mario, April 2025
 */

module pctang_top (
    input clk_g,                    // crystal clock

    input s1,

	input UART_RXD,
	output UART_TXD,

    output [7:0] led,

    // dualshock controller
    output ds_clk,
    input ds_miso,
    output ds_mosi,
    output ds_cs,
    output ds_clk2,
    input ds_miso2,
    output ds_mosi2,
    output ds_cs2,

    // USB1 and USB2
    inout usb1_dp,
    inout usb1_dn,
    inout usb2_dp,
    inout usb2_dn,

`ifdef VERILATOR
    input [7:0] kbd_data,           // PS2 keyboard data
    input kbd_req,                  // PS2 new data byte toggle
`endif

	// SDRAM
    output O_sdram_clk,
    output O_sdram_cke,
    output O_sdram_cs_n,            // chip select
    output O_sdram_cas_n,           // columns address select
    output O_sdram_ras_n,           // row address select
    output O_sdram_wen_n,           // write enable
    inout [15:0] IO_sdram_dq,       // bidirectional data bus
    output [12:0] O_sdram_addr,     // multiplexed address bus
    output [1:0] O_sdram_ba,        // two banks
    output [1:0] O_sdram_dqm,

    // HDMI TX
   output       tmds_clk_n,
   output       tmds_clk_p,
   output [2:0] tmds_d_n,
   output [2:0] tmds_d_p
);

//////////////////////////////////////////////////////////////////

`ifdef VERILATOR
logic reset = '0;
`else
logic reset = '1;
always_ff @(posedge clk_sys) begin
    reset_cnt <= reset_cnt == 0 ? 0 : reset_cnt - 1;
    if (reset_cnt == 0 
        /* && s1 == 1'b0 */
    ) begin       // press button to start everything
        reset <= 1'b0;
    end
end
`endif
wire overlay;       // default 1
logic loading_bios;
wire reset_cpu = loading_bios;
logic [19:0] reset_cnt = 20'hFFFFF;

// SDRAM DQ
wire [15:0] sdram_dq_out;
wire        sdram_dq_io;      // 0: output, 1: input
assign IO_sdram_dq = sdram_dq_io ? 16'hZZZZ : sdram_dq_out;

logic  biu_done;
logic  [7:0] clock_cycle_counter_division_ratio;
logic  [7:0] clock_cycle_counter_decrement_value;
logic        shift_read_timing;
logic  [1:0] ram_read_wait_cycle;
logic  [1:0] ram_write_wait_cycle;
logic        cycle_accrate;
logic  [1:0] clk_select = 3;        // 0: 4.77, 3: 12.5 (not cycle accurate)

////////////////// Clocks & CE //////////////////

logic clk_sys;          // 50Mhz clock for everything including MCL86 core
logic clk_56_875;       // 56.875Mhz HGC clock
logic clk_cpu;          // 4.77Mhz CE for MCL86 core
logic peripheral_clock; // 2.385Mhz
logic clk_pixel;        // 74.25Mhz 720p HDMI pixel clock
logic clk_5x_pixel;

`ifndef VERILATOR
pll pll_inst(
   .clkout0(clk_sys),    // 50Mhz
   .clkout1(O_sdram_clk),// 50Mhz, shifted 225 degrees
//   .clkout2(),           
//   .clkout3(), // HGC clock
   .clkin(clk_g) 
);
pll_27 pll_27_inst(
    .clkin(clk_g),
    .clkout0(clk27)
);
pll_74 pll_74_inst(
    .clkin(clk27),
    .clkout0(clk_pixel),
    .clkout1(clk_5x_pixel)
);
`else

assign clk_sys = clk_g;
assign clk_56_875 = clk_g;

`endif

logic  ce_cga /* verilator public */;           // 28.636Mhz CGA clock enable
logic [16:0] ce_cga_cnt;

always_ff @(posedge clk_sys) begin
    if (reset) begin
        ce_cga_cnt <= 0;
    end else begin
        ce_cga <= 1'b0;
        ce_cga_cnt <= ce_cga_cnt + 28636;
        if (ce_cga_cnt + 28636 >= 50000) begin
            ce_cga_cnt <= ce_cga_cnt + 28636 - 50000;
            ce_cga <= 1'b1;
        end
    end
end

logic  clk_cpu_ff_1;
logic  clk_cpu_ff_2;

logic  pclk_ff_1;
logic  pclk_ff_2;
logic  pclk;

// generate 4.77Mhz from 50Mhz
logic clk_4_77;         // 4.77Mhz CE
logic clk_12_5;         // 12.5Mhz CE
logic [11:0] cnt_4_77;
logic [2:0] cnt_12_5;
always @(posedge clk_sys) begin
    if (reset) begin
        clk_4_77 <= 1'b0;
        cnt_4_77 <= 0;
        clk_12_5 <= 1'b0;
        cnt_12_5 <= 0;
    end else begin
        cnt_4_77 <= cnt_4_77 + 477;
        if (cnt_4_77 + 477 >= 2500) begin
            cnt_4_77 <= cnt_4_77 + 477 - 2500;
            clk_4_77 <= ~clk_4_77;
            if (~clk_4_77)
                peripheral_clock <= ~peripheral_clock; // 2.385Mhz
        end
        cnt_12_5 <= cnt_12_5 + 1;
        if (cnt_12_5 + 1 >= 4) begin
            cnt_12_5 <= cnt_12_5 + 1 - 4;
            clk_12_5 <= ~clk_12_5;
        end
    end
end

// always @(posedge clk_4_77)
//     peripheral_clock <= ~peripheral_clock; // 2.385Mhz

always @(posedge clk_sys) begin
    if (reset) begin
        clk_cpu_ff_1    <= 1'b0;
        clk_cpu_ff_2    <= 1'b0;
        clk_cpu         <= 1'b0;
        pclk_ff_1       <= 1'b0;
        pclk_ff_2       <= 1'b0;
        pclk            <= 1'b0;
        cycle_accrate   <= 1'b1;
        clock_cycle_counter_division_ratio  <= 8'd1 - 8'd1;
        clock_cycle_counter_decrement_value <= 8'd1;
        shift_read_timing                   <= 1'b0;
        ram_read_wait_cycle                 <= 2'd0;
        ram_write_wait_cycle                <= 2'd0;
    end else begin
        clk_cpu_ff_2    <= clk_cpu_ff_1;
        clk_cpu         <= clk_cpu_ff_2;
        pclk_ff_1       <= peripheral_clock;
        pclk_ff_2       <= pclk_ff_1;
        pclk            <= pclk_ff_2;
        // nand2mario: default to 4.77Mhz
        clk_cpu_ff_1    <= clk_4_77;
        clock_cycle_counter_division_ratio  <= 8'd1 - 8'd1;
        clock_cycle_counter_decrement_value <= 8'd1;
        shift_read_timing                   <= 1'b0;
        ram_read_wait_cycle                 <= 2'd0;
        ram_write_wait_cycle                <= 2'd0;
        cycle_accrate                       <= 1'b1;
        
        // 12.5Mhz, non cycle accurate
        if (clk_select == 2'b11) begin                    
            clk_cpu_ff_1    <= clk_12_5;
            clock_cycle_counter_division_ratio  <= 8'd1 - 8'd1;
            clock_cycle_counter_decrement_value <= 8'd5;
            shift_read_timing                   <= 1'b1;
            ram_read_wait_cycle                 <= 2'd1;
            ram_write_wait_cycle                <= 2'd0;
            cycle_accrate                       <= 1'b0;
        end
    end
end

////////////////// Status configuration //////////////////

logic [63:0] status;

logic tandy_mode;
logic hgc_mode;
reg cga_hw;
reg hercules_hw;
logic hgc_mode_video_ff;

assign tandy_mode = status[3];
assign hgc_mode = status[4];
assign hgc_mode_video_ff = hgc_mode & ~tandy_mode;
assign cga_hw = ~status[44] | tandy_mode;
assign hercules_hw = ~status[45] & ~tandy_mode;

////////////////// BIOS loading //////////////////
wire initilized_sdram;

logic        bios_req;
logic [19:0] bios_address;
logic [7:0]  bios_write_data;
logic        bios_write;

`ifdef VERILATOR
// test bios loading in verilator
bios_loader u_bios_loader(
    .clk(clk_sys),
    .reset(reset),
    .initilized_sdram(initilized_sdram),
    .bios_request(bios_req),
    .bios_loading(loading_bios),
    .bios_address(bios_address),
    .bios_data(bios_write_data),
    .bios_we(bios_write)
);
`else
// bios loading from bl616
wire [7:0] loading_do;
wire loading_do_valid;
assign bios_req = loading_bios;
reg [19:0] bios_addr = 20'hF0000;
always_ff @(posedge clk_sys) begin
    bios_write <= 1'b0;
    if (loading_do_valid) begin
        bios_write_data <= loading_do;
        bios_write <= 1'b1;
        bios_address <= bios_addr;
        bios_addr <= bios_addr + 1;
    end
end
`endif

////////////////// Chipset & CPU //////////////////
logic [7:0] data_bus;
logic INTA_n;
logic [19:0] cpu_ad_out /* verilator public */;
logic [19:0] cpu_address /* verilator public */;
logic [7:0] cpu_data_bus;
wire processor_ready;
logic interrupt_to_cpu;
logic address_latch_enable;
logic address_direction;

logic lock_n;
logic [2:0] processor_status;

logic [3:0] dma_acknowledge_n;

logic [7:0] port_b_out;
logic [7:0] port_c_in;
logic [7:0] sw;

// [0]: 0: boot from floppy, 1: go to BASIC
// [1]: 0: 8087 present, 1: 8087 not present
// [3:2]: 11: one bank of memory, 10: two banks of memory, 01: three banks of memory, 00: four banks of memory
// [5:4]: 00: MDA, 01: 80-column CGA, 10: 40-column CGA, 11: No video or special
// [7:6]: 00: 1 floppy drive, 01: 2 floppy drives, 10: 3 floppy drives, 11: 4 floppy drives
assign sw = hgc_mode ? 8'b01111101 : 8'b01101101; // PCXT DIP Switches (HGC or CGA 80)
assign port_c_in[3:0] = port_b_out[3] ? sw[7:4] : sw[3:0];

// logic tandy_bios_flag = bios_write ? tandy_bios_write : tandy_mode;

localparam [27:0] cur_rate = 28'd50000000;

always_ff @(posedge clk_sys) begin
    if (address_latch_enable)
        cpu_address <= cpu_ad_out;
    else
        cpu_address <= cpu_address;
end

// Video
wire VGA_VBlank_border;
wire std_hsyncwidth;
wire pause_core;
wire swap_video;

wire HBlank /* verilator public */;
wire HSync /* verilator public */;
wire VBlank /* verilator public */;
wire VSync /* verilator public */;
wire [3:0] color_cga /* verilator public */;
reg ce_pixel_cga /* verilator public */;

wire ce_pixel_hgc;
wire de_o;
// wire [5:0] r, g, b;

// audio
wire speaker_out;

wire ps2_kbd_clk, ps2_kbd_clk_out;
wire ps2_kbd_data, ps2_kbd_data_out;

wire [15:0] mgmt_address;
wire        mgmt_read;
wire [15:0] mgmt_readdata;
wire        mgmt_write;
wire [15:0] mgmt_writedata;
wire [1:0]  fdd_request;


CHIPSET #(.clk_rate(cur_rate)) u_CHIPSET
(
    .clock                              (clk_sys),
    .clk_sys                            (clk_sys),
    .cpu_clock                          (clk_cpu),
    .peripheral_clock                   (pclk),
    .clk_select                         (clk_select),
    .reset                              (reset_cpu),
    .sdram_reset                        (1'b0),
    .cpu_address                        (cpu_address),
    .cpu_data_bus                       (cpu_data_bus),
    .processor_status                   (processor_status),
    .processor_lock_n                   (lock_n),
//	.processor_transmit_or_receive_n    (processor_transmit_or_receive_n),
    .processor_ready                    (processor_ready),
    .interrupt_to_cpu                   (interrupt_to_cpu),
    .splashscreen                       (1'b0),
    .std_hsyncwidth                     (std_hsyncwidth),
    .composite                          (1'b0),
    .video_output                       (hgc_mode_video_ff),
    .ce_cga                             (ce_cga),
    .enable_cga                         (1'b1),
    .clk_vga_hgc                        (clk_56_875),
    .enable_hgc                         (1'b1),
    .hgc_rgb                            (2'b10), // always B&W - monochrome monitor tint handled down below
//	.de_o                               (VGA_DE),
    .CGA                                (color_cga),
    .VGA_R                              (/*r*/),
    .VGA_G                              (/*g*/),
    .VGA_B                              (/*b*/),
    .VGA_HSYNC                          (HSync),
    .VGA_VSYNC                          (VSync),
    .VGA_HBlank                         (HBlank),
    .VGA_VBlank                         (VBlank),
    .VGA_VBlank_border                  (VGA_VBlank_border),
//	.address                            (address),
    .address_ext                        (bios_address),
    .ext_access_request                 (bios_req),
    .address_direction                  (address_direction),
    .data_bus                           (data_bus),
    .data_bus_ext                       (bios_write_data),
//	.data_bus_direction                 (data_bus_direction),
    .address_latch_enable               (address_latch_enable),
//  .io_channel_check                   (),
    .io_channel_ready                   (1'b1),
    .interrupt_request                  (0),    // use?	-> It does not seem to be necessary.
//  .io_read_n                          (io_read_n),
    .io_read_n_ext                      (1'b1),
//  .io_read_n_direction                (io_read_n_direction),
//  .io_write_n                         (io_write_n),
    .io_write_n_ext                     (1'b1),
//  .io_write_n_direction               (io_write_n_direction),
//  .memory_read_n                      (memory_read_n),
    .memory_read_n_ext                  (1'b1),
//  .memory_read_n_direction            (memory_read_n_direction),
//  .memory_write_n                     (memory_write_n),
    .memory_write_n_ext                 (~bios_write),
//  .memory_write_n_direction           (memory_write_n_direction),
    .dma_request                        (0),    // use?	-> I don't know if it will ever be necessary, at least not during testing.
    .dma_acknowledge_n                  (dma_acknowledge_n),
//  .address_enable_n                   (address_enable_n),
//  .terminal_count_n                   (terminal_count_n)
    .port_b_out                         (port_b_out),
    .port_c_in                          (port_c_in),
    .port_b_in                          (port_b_out),
    .speaker_out                        (speaker_out),
    .ps2_clock                          (ps2_kbd_clk),
    .ps2_data                           (ps2_kbd_data),
    .ps2_clock_out                      (ps2_kbd_clk_out),
    .ps2_data_out                       (ps2_kbd_data_out),
    .ps2_mouseclk_in                    (/*ps2_mouse_clk_out*/),
    .ps2_mousedat_in                    (/*ps2_mouse_data_out*/),
    .ps2_mouseclk_out                   (/*ps2_mouse_clk_in*/),
    .ps2_mousedat_out                   (/*ps2_mouse_data_in*/),
    .joy_opts                           (/*joy_opts*/),           //Joy0-Disabled, Joy0-Type, Joy1-Disabled, Joy1-Type, turbo_sync
    .joy0                               (/*status[28] ? joy1 : joy0*/),
    .joy1                               (/*status[28] ? joy0 : joy1*/),
    .joya0                              (/*status[28] ? joya1 : joya0*/),
    .joya1                              (/*status[28] ? joya0 : joya1*/),
    .jtopl2_snd_e                       (/*jtopl2_snd_e*/),
    .tandy_snd_e                        (/*tandy_snd_e*/),
    .opl2_io                            (/*xtctl[4] ? 2'b10 : status[43:42]*/),
    .cms_en                             (~status[10]),
    .o_cms_l                            (/*cms_l_snd_e*/),
    .o_cms_r                            (/*cms_r_snd_e*/),
    .tandy_video                        (tandy_mode),
    .tandy_bios_flag                    (1'b0 /*tandy_bios_flag*/),
    .tandy_16_gfx                       (/*tandy_16_gfx*/),
    .tandy_color_16                     (/*tandy_color_16*/),
    .clk_uart                           (/*clk_uart2_en*/),
    .uart2_rx                           (/*uart_rx*/),
    .uart2_tx                           (/*uart_tx*/),
    .uart2_cts_n                        (/*uart_cts*/),
    .uart2_dcd_n                        (/*uart_dcd*/),
    .uart2_dsr_n                        (/*uart_dsr*/),
    .uart2_rts_n                        (/*uart_rts*/),
    .uart2_dtr_n                        (/*uart_dtr*/),
    .enable_sdram                       (1'b1),
    .initilized_sdram                   (initilized_sdram),
    .sdram_clock                        (clk_sys),
    .sdram_address                      (O_sdram_addr),
    .sdram_cke                          (O_sdram_cke),
    .sdram_cs                           (O_sdram_cs_n),
    .sdram_ras                          (O_sdram_ras_n),
    .sdram_cas                          (O_sdram_cas_n),
    .sdram_we                           (O_sdram_wen_n),
    .sdram_ba                           (O_sdram_ba),
    .sdram_dq_in                        (IO_sdram_dq),
    .sdram_dq_out                       (sdram_dq_out),
    .sdram_dq_io                        (sdram_dq_io),
    .sdram_ldqm                         (O_sdram_dqm[0]),
    .sdram_udqm                         (O_sdram_dqm[1]),
    .ems_enabled                        (~status[11]),
    .ems_address                        (status[13:12]),
    .bios_protect_flag                  (bios_req ? 2'b00 : 2'b11),
    .use_mmc                            (/*use_mmc*/),
    .spi_clk                            (/*spi_clk*/),
    .spi_cs                             (/*spi_cs*/),
    .spi_mosi                           (/*spi_mosi*/),
    .spi_miso                           (/*spi_miso*/),
    .mgmt_readdata                      (mgmt_readdata),
    .mgmt_writedata                     (mgmt_writedata),
    .mgmt_address                       (mgmt_address),
    .mgmt_write                         (mgmt_write),
    .mgmt_read                          (mgmt_read),
    .floppy_wp                          (status[20:19]),
    .fdd_request                        (fdd_request),
    .ide0_request                       (/*mgmt_req[2:0]*/),
    .xtctl                              (/*xtctl*/),
    .enable_a000h                       (/*a000h*/),
    .wait_count_clk_en                  (~clk_cpu & clk_cpu_ff_2),
    .ram_read_wait_cycle                (ram_read_wait_cycle),
    .ram_write_wait_cycle               (ram_write_wait_cycle),
    .pause_core                         (pause_core),
    .cga_hw                             (cga_hw),
    .hercules_hw                        (hercules_hw),
    .swap_video                         (swap_video),
    .crt_h_offset                       (status[49:46]),
    .crt_v_offset                       (status[52:50])
);

i8088 u_cpu
(
    .CORE_CLK(clk_sys),
    .CLK(clk_cpu),

    .RESET(reset_cpu),
    .READY(processor_ready && ~pause_core),
    .NMI(1'b0),
    .INTR(interrupt_to_cpu),

    .ad_out(cpu_ad_out),
    .dout(cpu_data_bus),
    .din(data_bus),

    .lock_n(lock_n),
    .s6_3_mux(/*s6_3_mux*/),
    .s2_s0_out(processor_status),
    .SEGMENT(/*SEGMENT*/),

    .biu_done(biu_done),
    .cycle_accrate(cycle_accrate),
    .clock_cycle_counter_division_ratio(clock_cycle_counter_division_ratio),
    .clock_cycle_counter_decrement_value(clock_cycle_counter_decrement_value),
    .shift_read_timing(shift_read_timing)
);

assign led = ~{4'b0, fdd_request[0] | fdd_request[1], overlay, reset_cpu, reset};

// reg [19:0] cpu_ad_r;
// always_ff @(posedge clk_sys) begin
//     cpu_ad_r <= cpu_ad_out;
//     if (cpu_ad_r != cpu_ad_out) begin
//         case (cpu_ad_out)
//         20'hfe165, 20'hfe192, 20'hfe1ce, 20'hfe20e, 20'hfe245:
//             $display("PC=%h", cpu_ad_out);
//         20'hfe2aa:
//             $display("PC=%h, display horizontal bar", cpu_ad_out);
//         20'hfe305:
//             $display("PC=%h, display cursor", cpu_ad_out);
//         20'hfe339:
//             $display("PC=%h, interrupt controller test", cpu_ad_out);
//         20'hfe3a2:
//             $display("PC=%h, Keyboard test", cpu_ad_out);
//         default: ;
//         endcase
//     end

// end

////////////////// Devices - PS2 keyboard //////////////////

`ifndef VERILATOR
logic [7:0] kbd_data;
`endif
logic kbd_data_valid;
logic clk_ps2;
localparam PS2DIV = 2000;       // 50M / 4000 = 12.5kHz
logic [8:0] kbd_host_data;
logic kbd_host_data_clear;
assign kbd_host_data_clear = '1;    // clear kbd data from PCXT automatically

always_ff @(posedge clk_sys) begin
    integer cnt;
    cnt <= cnt + 1;
    if (cnt == PS2DIV) begin
        clk_ps2 <= ~clk_ps2;
        cnt <= 0;
    end
end

ps2_device ps2_kbd(
    .clk_sys(clk_sys),
    .ps2_clk(clk_ps2),

    .wdata(kbd_data),               // keyboard data byte
    .we(kbd_data_valid),

    .ps2_clk_out(ps2_kbd_clk),      // emulated PS2 interface to PCXT
    .ps2_dat_out(ps2_kbd_data),
    .tx_empty(),
    .ps2_clk_in(ps2_kbd_clk_out),   // data from PCXT
    .ps2_dat_in(ps2_kbd_data_out),

    .rdata(kbd_host_data),          // {valid, data_byte_from_PCXT}
    .rd(kbd_host_data_clear)        // clear the data
);

`ifdef VERILATOR

logic kbd_req_r;

always_ff @(posedge clk_sys) begin
    kbd_req_r <= kbd_req;
    kbd_data_valid <= kbd_req_r ^ kbd_req;
end

`endif


////////////////// io to bl616 //////////////////

`ifndef VERILATOR
wire [7:0] overlay_x;
wire [7:0] overlay_y;
wire [14:0] overlay_color;

iosys_bl616 #(.COLOR_LOGO(15'b10000_10000_01000), .FREQ(50_000_000), .CORE_ID(6), .LOADING_STATE(1))
    sys_inst (
    .clk(clk_sys), .hclk(clk_pixel), .resetn(1'b1),

    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .joy1(joy1_btns | joy1_usb), .joy2(joy2_btns | joy2_usb),
    .hid1(joy1_mcu), .hid2(joy2_mcu),
    .uart_tx(UART_TXD), .uart_rx(UART_RXD),

    .mgmt_address(mgmt_address),        // fdd data
    .mgmt_read(mgmt_read),
    .mgmt_readdata(mgmt_readdata),
    .mgmt_write(mgmt_write),
    .mgmt_writedata(mgmt_writedata),
    .fdd_request(fdd_request),

    .kbd_data(kbd_data), .kbd_data_valid(kbd_data_valid),  // keyboard data

    .rom_loading(loading_bios), .rom_do(loading_do), .rom_do_valid(loading_do_valid)   // bios loading
);

`else

floppy_media_sim #(.FILENAME("floppy.hex")) floppy_media_inst (
    .clk(clk_sys),
    .reset(reset_cpu),

    .mgmt_address(mgmt_address),
    .mgmt_read(mgmt_read),
    .mgmt_readdata(mgmt_readdata),
    .mgmt_write(mgmt_write),
    .mgmt_writedata(mgmt_writedata),
    .fdd_request(fdd_request)
);

`endif

////////////////// Video output //////////////////

reg ce_pixel_cga_toggle;
always @(posedge clk_sys) begin
    if (ce_cga) begin
        ce_pixel_cga_toggle <= ~ce_pixel_cga_toggle;      // 14.318Mhz pixel clock
    end
end

assign ce_pixel_cga = ce_cga & ce_pixel_cga_toggle;

`ifndef VERILATOR
cga2hdmi cga2hdmi_inst(
    .clk(clk_sys), 
    .resetn(1'b1),
    
    .ce_pixel(ce_pixel_cga),
    .hblank(HBlank),
    .vblank(VBlank),
    .color(color_cga),

    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),

    .audio_l({speaker_out, 13'd0}), .audio_r({speaker_out, 13'd0}),

    .clk_pixel(clk_pixel),
    .clk_5x_pixel(clk_5x_pixel),
	.tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p), .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);
`endif

endmodule

