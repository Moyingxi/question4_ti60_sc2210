`timescale 1ns/1ps
// Unmodified user-specified camera demo: establish its effective RAW phase.
module tb_v8_demo_color;
    localparam W=64,H=32;
    reg clk=0,rst_n=0,vs=0,de=0;
    always #5 clk=~clk;
    reg [7:0] raw=0;
    wire ov,oh,hs; wire [7:0] r,g,b;
    VIP_RAW8_RGB888 #(W,H) ref_demo(clk,rst_n,2'd0,vs,de,1'b0,raw,ov,oh,hs,r,g,b);
    integer phase,x,y,rx,ry,n,correct,matched;
    reg oq;
    function [7:0] sample(input integer xx,yy,pp);
        case(({yy[0],xx[0]} ^ pp))
            0:sample=8'd40; // B
            3:sample=8'd220;// R
            default:sample=8'd110;// G
        endcase
    endfunction
    always @(posedge clk) begin
        #1;
        if(!rst_n) begin rx=0;ry=0;oq=0;n=0;correct=0;end
        else begin
            if(oq&&!oh) begin rx=0;ry=ry+1;end
            if(oh) begin
                if(ry>=4&&ry<H-2&&rx>=4&&rx<W-4) begin
                    n=n+1;
                    if({r,g,b}===24'hdc6e28) correct=correct+1;
                    if(ry==6 && rx==10) $display("DEMO phase=%0d RGB=%02x %02x %02x",phase,r,g,b);
                end
                rx=rx+1;
            end
            oq=oh;
        end
    end
    initial begin
        matched=-1;
        for(phase=0;phase<4;phase=phase+1) begin
            @(negedge clk);rst_n=0;vs=0;de=0;
            repeat(10) @(negedge clk);
            rst_n=1;vs=1;
            for(y=0;y<H;y=y+1) begin
                repeat(20) @(negedge clk);
                for(x=0;x<W;x=x+1) begin
                    de=1;raw=sample(x,y,phase);@(negedge clk);
                end
                de=0;
            end
            repeat(30) @(negedge clk);
            $display("DEMO phase=%0d exact=%0d/%0d",phase,correct,n);
            if(correct==n && n>100) matched=phase;
        end
        if(matched!=0) $fatal(1,"Demo expected BGGR, matched XOR phase %0d",matched);
        $display("PASS tb_v8_demo_color: unchanged demo accepts BGGR RAW");
        $finish;
    end
endmodule
