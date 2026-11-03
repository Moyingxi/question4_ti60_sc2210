`timescale 1ns/1ps
// Explicit native RAM10 aspect ratios. The generic deep-array inference picks
// narrower modes and wastes blocks here. Used as 13x1024x10 mask storage and
// 8x512x20 statistics storage. XSim uses the installed vendor's actual model.
module v8_shape_ram #(
    parameter WIDTH=10,ROW_BITS=10,BANK_BITS=4,BANKS=13
)(
    input clk,write_enable,
    input [ROW_BITS+BANK_BITS-1:0] write_address,read_address,
    input [WIDTH-1:0] write_data,
    output [WIDTH-1:0] read_data
);
    wire [WIDTH-1:0] bank_data[0:BANKS-1];
    reg [BANK_BITS-1:0] bank_q;
    always @(posedge clk)bank_q<=read_address[ROW_BITS+:BANK_BITS];
    assign read_data=bank_data[bank_q];
    genvar b;
    generate for(b=0;b<BANKS;b=b+1)begin:bank
        wire selected=write_enable && write_address[ROW_BITS+:BANK_BITS]==b;
        EFX_RAM10 #(.READ_WIDTH(WIDTH),.WRITE_WIDTH(WIDTH),
                    .OUTPUT_REG(1'b0),.WRITE_MODE("READ_FIRST")) ram(
            .WCLK(clk),.WCLKE(selected),.WADDREN(1'b1),.WE({selected,selected}),
            .WDATA(write_data),.WADDR(write_address[ROW_BITS-1:0]),
            .RCLK(clk),.RE(read_address[ROW_BITS+:BANK_BITS]==b),.RADDREN(1'b1),.RST(1'b0),
            .RADDR(read_address[ROW_BITS-1:0]),.RDATA(bank_data[b])
        );
    end endgenerate
endmodule
