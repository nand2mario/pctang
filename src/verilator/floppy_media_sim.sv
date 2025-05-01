// simulated 360KB floppy media
// 
// Author: nand2mario, 4/2025

module floppy_media_sim #(
    parameter FILENAME
) (
    input clk,
    input reset,
    
    output reg [15:0] mgmt_address,
    output reg        mgmt_read,
    input      [15:0] mgmt_readdata,
    output reg        mgmt_write,
    output reg [15:0] mgmt_writedata,
    input       [1:0] fdd_request
);

reg [7:0] mem [0:360*1024-1];

initial begin
    $readmemh(FILENAME, mem);
end

typedef enum {
    INIT_MEDIA,
    IDLE,
    GET_SECTOR,
    GET_SECTOR_WAIT,
    READ_DATA,
    WRITE_DATA,
    DONE_WAIT
} state_t;

state_t st = IDLE;
reg [8:0] cnt;

typedef struct {
    logic [7:0] address;
    logic [7:0] data;
} mgmt_msg_t;

// Initial settings for floppy media: 
// 0x00.[0]:      media present
// 0x01.[0]:      media writeprotect
// 0x02.[7:0]:    media cylinders
// 0x03.[7:0]:    media sectors per track
// 0x04.[31:0]:   media total sector count
// 0x05.[1:0]:    media heads
localparam [7:0] INIT_ADDR[6] = '{0, 1, 2,  3, 4, 5};
localparam [15:0] INIT_DATA[6] =  '{1, 0, 40, 9, 720, 2};

logic read_request;
logic drive;
logic [14:0] sector;

always @(posedge clk) begin
    if (reset) begin
        mgmt_address <= 0;
        mgmt_read <= 0;
        mgmt_write <= 0;
        mgmt_writedata <= 0;
        st <= INIT_MEDIA;
    end else begin
        mgmt_write <= 0;
        mgmt_read <= 0;
        mgmt_address[15:8] <= 8'hF2;
        case (st)
            INIT_MEDIA: begin
                if (cnt < 6) begin
                    mgmt_address[7:0] <= INIT_ADDR[cnt];
                    mgmt_writedata <= INIT_DATA[cnt];
                    mgmt_write <= 1;
                    $display("INIT: addr %d, data %d", mgmt_address, mgmt_writedata);
                end else begin
                    st <= IDLE;
                end
                cnt <= cnt + 1;
            end
            IDLE: begin
                if (fdd_request) begin
                    read_request <= fdd_request[0];
                    st <= GET_SECTOR;
                    cnt <= 0;
                end
            end
            GET_SECTOR: begin
                mgmt_address[7:0] <= 0;
                mgmt_read <= 1;
                st <= GET_SECTOR_WAIT;
            end
            GET_SECTOR_WAIT: begin
                {drive,sector} <= mgmt_readdata;
                cnt <= 0;
                st <= read_request ? READ_DATA : WRITE_DATA;
                if (read_request) begin
                    $display("READ: drive %d, sector %d", drive, sector);
                end else begin
                    $display("WRITE: drive %d, sector %d", drive, sector);
                end
                mgmt_address[7:0] <= 'h0f;
            end
            READ_DATA: begin         // feed sector data to FPGA FIFO by writing to management address 0xf
                mgmt_write <= 1;
                mgmt_writedata <= mem[{sector,cnt}];
                cnt <= cnt + 1;
                if (cnt == 511) begin
                    st <= DONE_WAIT;
                    $display("Read done");
                end
            end 
            WRITE_DATA: begin       // fetch data from FPGA FIFO and write to floppy media
                mgmt_read <= 1;
                mem[{sector,cnt}] <= mgmt_readdata;
                cnt <= cnt + 1;
                if (cnt == 511) begin
                    st <= DONE_WAIT;
                    $display("Write done");
                end
            end
            DONE_WAIT: begin
                cnt <= cnt + 1;
                if (cnt == 15) begin
                    st <= IDLE;
                    $display("Returning to IDLE");
                end
            end
            default: ;
        endcase
    end
end
endmodule