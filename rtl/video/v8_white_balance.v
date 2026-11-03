`timescale 1ns/1ps
// Three CE-enabled stages, matching rgb_to_y8 latency. Q8 gain, round-to-nearest
// and saturate; bypass forces unity. Configuration is latched by the frontend
// at processing-frame start. This changes color metadata only, not algorithm Y.
module v8_white_balance(
    input clk,rst_n,ce,s_valid,input [23:0] rgb,input [36:0] config_word,
    output reg m_valid,output reg [23:0] corrected
);
    wire [11:0] gr=config_word[36]?config_word[11:0]:12'd256;
    wire [11:0] gg=config_word[36]?config_word[23:12]:12'd256;
    wire [11:0] gb=config_word[36]?config_word[35:24]:12'd256;
    reg [19:0] pr,pg,pb;
    reg [23:0] rounded;
    reg v0,v1;
    function [7:0] quantize;
        input [19:0] value;
        reg [20:0] q;
        begin q={1'b0,value}+21'd128;quantize=(q>=21'd65280)?8'd255:q[15:8];end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin v0<=0;v1<=0;m_valid<=0;corrected<=0;pr<=0;pg<=0;pb<=0;rounded<=0;end
        else if(ce) begin
            v0<=s_valid;v1<=v0;m_valid<=v1;
            pr<=rgb[23:16]*gr;pg<=rgb[15:8]*gg;pb<=rgb[7:0]*gb;
            rounded<={quantize(pr),quantize(pg),quantize(pb)};
            corrected<=rounded;
        end
    end
endmodule
