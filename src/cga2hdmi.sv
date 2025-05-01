
module cga2hdmi (
	input clk,          
	input resetn,

    // CGA video signals (640x200x60, 4-bit RGBI)
    input hblank,
    input vblank,
    input [3:0] color,
    input ce_pixel,         // 28.636Mhz

    input [15:0] audio_l,
    input [15:0] audio_r,

    // overlay interface
    input overlay,
    output [7:0] overlay_x,
    output [7:0] overlay_y,
    input [14:0] overlay_color, // BGR5

	// video clocks
	input clk_pixel,
	input clk_5x_pixel,

	// output signals
	output       tmds_clk_n,
	output       tmds_clk_p,
	output [2:0] tmds_d_n,
	output [2:0] tmds_d_p
);

localparam CLKFRQ = 74250;
localparam AUDIO_BIT_WIDTH = 16;

// video stuff
wire [9:0] cy;
wire [10:0] cx;

//
// BRAM frame buffer
//
localparam MEM_DEPTH=640*200;

logic [3:0] mem [0:MEM_DEPTH-1];       // 64 KB
logic [16:0] mem_portA_addr;
logic [3:0] mem_portA_wdata;           // IRGB
logic mem_portA_we;

logic [16:0] mem_portB_addr;
logic [3:0] mem_portB_rdata;

// BRAM port A read/write
always @(posedge clk) begin
    if (mem_portA_we) begin
        mem[mem_portA_addr] <= mem_portA_wdata;
    end
end

// BRAM port B read
always @(posedge clk_pixel) begin
    mem_portB_rdata <= mem[mem_portB_addr];
end

// 
// Data input and initial background loading
//
logic [9:0] x;      // 0...639
logic [7:0] y;      // 0...199
logic hblank_r;
// always @(posedge clk) begin
//     mem_portA_we <= 1'b0;
//     hblank_r <= hblank;
//     if (vblank) begin
//         x <= 0;
//         y <= 0;
//     end else if (hblank & ~hblank_r) begin
//         x <= 0;
//         y <= y + 1;
//     end else if (~hblank & ce_pixel & x < 640 & y < 200) begin
//         x <= x + 1;
//         mem_portA_addr <= y * 640 + x;
//         mem_portA_wdata <= color;
//         mem_portA_we <= 1'b1;
//     end
// end

always @(posedge clk) begin
    mem_portA_we <= 1'b0;
    hblank_r <= hblank;
    if (vblank) begin
        mem_portA_addr <= 0;
    end else if (~hblank & ce_pixel) begin
        mem_portA_addr <= mem_portA_addr + 1;
        mem_portA_wdata <= color;
        mem_portA_we <= 1'b1;
    end
end

// audio stuff
localparam AUDIO_RATE=48000;
localparam AUDIO_CLK_DELAY = CLKFRQ * 1000 / AUDIO_RATE / 2;
logic [$clog2(AUDIO_CLK_DELAY)-1:0] audio_divider;
logic clk_audio;

always_ff@(posedge clk_pixel) 
begin
    if (audio_divider != AUDIO_CLK_DELAY - 1) 
        audio_divider++;
    else begin 
        clk_audio <= ~clk_audio; 
        audio_divider <= 0; 
    end
end

// TODO: need to use async fifo to cross clock domains
reg [15:0] audio_sample_word [1:0], audio_sample_word0 [1:0];
always @(posedge clk_pixel) begin
    audio_sample_word0[0] <= audio_l;
    audio_sample_word[0] <= audio_sample_word0[0];
    audio_sample_word0[1] <= audio_r;
    audio_sample_word[1] <= audio_sample_word0[1];
end

//
// Video
// Scale SMS image from 256x192 to 960x720
// Scale overlay image from 256x224 to 960x720
//
reg [23:0] rgb;             // actual RGB output
reg active;
reg [$clog2(640)-1:0] xx;   // scaled-down pixel position
reg [$clog2(200)-1:0] yy;
reg [10:0] xcnt;
reg [10:0] ycnt;            // fractional scaling counters
reg [9:0] cy_r;
assign mem_portB_addr = yy * 640 + xx;
assign overlay_x = xx;
assign overlay_y = yy;
localparam XSTART = (1280 - 960) / 2;   // 960:720 = 4:3
localparam XSTOP = (1280 + 960) / 2;

reg overlay_r, overlay_rr;
always @(posedge clk_pixel) begin
    overlay_r <= overlay; overlay_rr <= overlay_r;
end

// address calculation
// Assume the video occupies fully on the Y direction, we are upscaling the video by `720/height`.
// xcnt and ycnt are fractional scaling counters.
always @(posedge clk_pixel) begin
    reg active_t;
    reg [10:0] xcnt_next;
    reg [10:0] ycnt_next;
    xcnt_next = xcnt + (overlay_rr ? 256 : 640);
    ycnt_next = ycnt + (overlay_rr ? 224 : 200);

    active_t = 0;
    if (cx == XSTART - 1) begin
        active_t = 1;
        active <= 1;
    end else if (cx == XSTOP - 1) begin
        active_t = 0;
        active <= 0;
    end

    if (active_t | active) begin        // increment xx
        xcnt <= xcnt_next;
        if (xcnt_next >= 960) begin
            xcnt <= xcnt_next - 960;
            xx <= xx + 1;
        end
    end

    cy_r <= cy;
    if (cy[0] != cy_r[0]) begin         // increment yy at new lines
        ycnt <= ycnt_next;
        if (ycnt_next >= 720) begin
            ycnt <= ycnt_next - 720;
            yy <= yy + 1;
        end
    end

    if (cx == 0) begin
        xx <= 0;
        xcnt <= 0;
    end
    
    if (cy == 0) begin
        yy <= 0;
        ycnt <= 0;
    end 

end

// calc rgb value to hdmi
always @(posedge clk_pixel) begin
    if (active) begin
        if (overlay_rr)
            rgb <= {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0};       // BGR5 to RGB8
        else
            rgb <= /* yy == 5 ? 24'h008000 : */ cga_to_rgb(mem_portB_rdata);   // IRGB to RGB8
    end else begin
        logic [7:0] grad = 8'h30 + cy[9:5];
        rgb <= {grad, grad, grad};
    end
end

// HDMI output.
logic[2:0] tmds;

localparam VIDEOID = 4;
localparam VIDEO_REFRESH = 60.0;

hdmi #( .VIDEO_ID_CODE(VIDEOID), 
        .DVI_OUTPUT(0), 
        .VIDEO_REFRESH_RATE(VIDEO_REFRESH),
        .IT_CONTENT(1),
        .AUDIO_RATE(AUDIO_RATE), 
        .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
        .START_X(0),
        .START_Y(0) )

hdmi( .clk_pixel_x5(clk_5x_pixel), 
        .clk_pixel(clk_pixel), 
        .clk_audio(clk_audio),
        .rgb(rgb), 
        .reset( 0 ),
        .audio_sample_word(audio_sample_word),
        .tmds(tmds), 
        .tmds_clock(tmdsClk), 
        .cx(cx), 
        .cy(cy),
        .frame_width( ),
        .frame_height( ) );

// Gowin LVDS output buffer
ELVDS_OBUF tmds_bufds [3:0] (
    .I({clk_pixel, tmds}),
    .O({tmds_clk_p, tmds_d_p}),
    .OB({tmds_clk_n, tmds_d_n})
);

function [23:0] cga_to_rgb (input [3:0] video);
    case (video)
        4'h0: cga_to_rgb = 24'b00000000_00000000_00000000;
        4'h1: cga_to_rgb = 24'b10101010_00000000_00000000;
        4'h2: cga_to_rgb = 24'b00000000_10101010_00000000;
        4'h3: cga_to_rgb = 24'b10101010_10101010_00000000;
        4'h4: cga_to_rgb = 24'b00000000_00000000_10101010;
        4'h5: cga_to_rgb = 24'b10101010_00000000_10101010;
        4'h6: cga_to_rgb = 24'b00000000_01010101_10101010; // Brown!
        4'h7: cga_to_rgb = 24'b10101010_10101010_10101010;
        4'h8: cga_to_rgb = 24'b01010101_01010101_01010101;
        4'h9: cga_to_rgb = 24'b11111111_01010101_01010101;
        4'hA: cga_to_rgb = 24'b01010101_11111111_01010101;
        4'hB: cga_to_rgb = 24'b11111111_11111111_01010101;
        4'hC: cga_to_rgb = 24'b01010101_01010101_11111111;
        4'hD: cga_to_rgb = 24'b11111111_01010101_11111111;
        4'hE: cga_to_rgb = 24'b01010101_11111111_11111111;
        4'hF: cga_to_rgb = 24'b11111111_11111111_11111111;
    endcase
endfunction

endmodule
