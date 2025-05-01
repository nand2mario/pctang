module bios_loader(
    input             clk,
    input             reset,
    input             initilized_sdram,
    output reg        bios_loading,
    output            bios_request,
    output reg [19:0] bios_address,
    output      [7:0] bios_data,
    output            bios_we
);

reg [1:0]  bios_protect_flag = 2'b11;
reg [4:0]  bios_load_state = 4'h0;
reg [7:0]  bios_write_wait_cnt;
reg        bios_write_byte_cnt;
reg        tandy_bios_write;

// 64KB of ROM ($F0000-$FFFFF)
logic [7:0] rom [0:64*1024-1];

initial begin
    $readmemh("pcxt_ibm5160_bios.hex", rom);
end

// load ROM into SDRAM when reset
logic [1:0] rom_load_state;
localparam ROM_LOAD_IDLE = 2'd0;
localparam ROM_LOAD_REQ = 2'd1;
localparam ROM_LOAD_WAIT = 2'd2;
localparam ROM_LOAD_DONE = 2'd3;
always_ff @(posedge clk) begin
    if (reset) begin
        bios_loading <= 1'b1;
        rom_load_state <= ROM_LOAD_IDLE;
        bios_address <= 20'hF0000;
        bios_we <= 1'b0;
    end else begin
        bios_we <= 1'b0;
        case (rom_load_state)
            ROM_LOAD_IDLE: begin
                bios_protect_flag <= 2'b11;
                if (initilized_sdram) begin
                    rom_load_state <= ROM_LOAD_REQ;
                    bios_address <= 20'hF0000;
                    bios_request <= 1'b1;
                    bios_loading <= 1'b1;
                end
            end
            ROM_LOAD_REQ: begin
                bios_we <= 1'b1;
                bios_data <= rom[bios_address[15:0]];
                rom_load_state <= ROM_LOAD_WAIT;
                bios_write_wait_cnt <= 0;
            end
            ROM_LOAD_WAIT: begin
                bios_we <= 1'b0;
                bios_write_wait_cnt <= bios_write_wait_cnt + 1;
                if (bios_write_wait_cnt == 'h40) begin
                    rom_load_state <= ROM_LOAD_REQ;
                    bios_address <= bios_address + 1;
                    if (bios_address == 20'hFFFFF) begin
                        rom_load_state <= ROM_LOAD_DONE;
                    end
                end
            end
            ROM_LOAD_DONE: begin
                bios_loading <= 1'b0;
                bios_request <= 1'b0;
            end
        endcase
    end
end

endmodule