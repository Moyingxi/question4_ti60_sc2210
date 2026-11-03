`timescale 1ns/1ps
// Little-endian bit-stream packing; used only for lengths exactly divisible
// by both widths. Frame reset must not discard pending output data.
module v8_gearbox #(parameter IW=96,OW=128)(
    input clk,rst_n,clear,input [IW-1:0] s_data,input s_valid,output s_ready,
    output [OW-1:0] m_data,output m_valid,input m_ready
);
    localparam BW=IW+OW;
    reg [BW-1:0] bits,next_bits;
    reg [8:0] count,next_count;
    wire pop=m_valid && m_ready;
    assign s_ready=count<=OW;
    wire push=s_valid && s_ready;
    assign m_valid=count>=OW;
    assign m_data=bits[OW-1:0];
    always @* begin
        next_bits=pop?(bits>>OW):bits;
        next_count=pop?(count-OW):count;
        if(push) begin
            next_bits=next_bits|({{OW{1'b0}},s_data}<<next_count);
            next_count=next_count+IW;
        end
    end
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin bits<=0;count<=0;end
        else if(clear) begin bits<=0;count<=0;end
        else begin bits<=next_bits;count<=next_count;end
endmodule
