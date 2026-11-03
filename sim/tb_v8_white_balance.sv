`timescale 1ns/1ps
module tb_v8_white_balance;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0,valid=0;
    reg [23:0] rgb=0;reg [36:0] cfg=0;
    wire ov;wire [23:0] corrected;
    v8_white_balance dut(clk,rst_n,ce,valid,rgb,cfg,ov,corrected);
    reg [2:0] expected_valid=0;reg [23:0] expected[0:2];
    integer t,i,gain_index,checks=0;
    integer gains[0:6];reg [23:0] value;
    function [7:0] channel(input integer raw,gain);
        integer q;
        begin q=(raw*gain+128)/256;channel=q>255?255:q;end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin expected_valid=0;expected[0]=0;expected[1]=0;expected[2]=0;end
        else if(ce) begin
            expected_valid={expected_valid[1:0],valid};
            expected[2]=expected[1];expected[1]=expected[0];
            expected[0]={channel(rgb[23:16],cfg[36]?cfg[11:0]:256),
                         channel(rgb[15:8],cfg[36]?cfg[23:12]:256),
                         channel(rgb[7:0],cfg[36]?cfg[35:24]:256)};
        end
        #1;
        if(ov!==expected_valid[2] || (ov && corrected!==expected[2]))
            $fatal(1,"WB pipeline valid/round/saturation/CE mismatch got=%h expected=%h",corrected,expected[2]);
        if(ov && ce) checks=checks+1;
    end
    initial begin
        gains[0]=0;gains[1]=1;gains[2]=128;gains[3]=256;gains[4]=339;gains[5]=453;gains[6]=4095;
        repeat(4) @(negedge clk);rst_n=1;
        for(gain_index=0;gain_index<7;gain_index=gain_index+1)
            for(i=0;i<256;i=i+1) begin
                @(negedge clk);ce=1;valid=1;rgb={8'(i),8'(255-i),8'((i*73)%256)};
                cfg={1'b1,12'(gains[(gain_index+2)%7]),12'(gains[(gain_index+1)%7]),12'(gains[gain_index])};
                if(i%7==0) begin @(negedge clk);ce=0;repeat(3) @(negedge clk);ce=1;valid=0;end
            end
        for(i=0;i<256;i=i+1) begin
            @(negedge clk);valid=1;ce=1;cfg=37'h0fffffffff;rgb={8'(i),8'(255-i),8'(i)};
        end
        @(negedge clk);valid=0;repeat(6) @(negedge clk);
        if(checks<2048) $fatal(1,"insufficient checks");
        $display("PASS V8 WB: 2048 samples, all byte inputs, unity/bypass, Q8 rounding, zero/max gains, clipping, bubbles and CE stalls");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
