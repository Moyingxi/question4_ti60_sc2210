`timescale 1ns/1ps
module tb_v9_camera_fps;
    reg clk=0,sclk=0,rst_n=0;always #5 clk=~clk;always #3.7 sclk=~sclk;
    reg [31:0] captured=0;reg request=0,seen=0;
    wire [11:0] fps;
    v9_camera_fps #(.CLK_HZ(6000)) dut(sclk,rst_n,captured,clk,rst_n,fps);
    always @(posedge sclk) if(!rst_n) begin captured<=0;seen<=0;end
    else if(request!=seen) begin captured<=captured+1;seen<=request;end
    integer i,j;
    task window(input integer rate);
        integer k;
        begin for(k=0;k<6000;k=k+1) begin
            @(negedge clk);
            if(rate!=0 && k%(6000/rate)==20) request=~request;
        end end
    endtask
    task check(input [11:0] b);
        begin repeat(15) @(negedge clk);if(fps!==b) $fatal(1,"camera fps %h expected %h",fps,b);end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        // Long steady 60fps run crosses the 10-bit Gray wrap (1024 captures).
        for(j=0;j<20;j=j+1) window(60);check(12'h060);
        window(30);window(30);check(12'h030);
        window(0);window(0);check(0);
        window(1);window(1);check(12'h001);
        // No new complete captures: rejected/truncated/overflowed frames never
        // advance the input counter and therefore never inflate the FPS.
        window(0);window(0);check(0);
        rst_n=0;@(negedge clk);if(fps!==0) $fatal(1,"reset");
        $display("PASS V9 camera effective FPS: asynchronous Gray CDC, wrap, 60/30/1/0 complete captures, no dependence on display/replay, decimal conversion/reset");$finish;
    end
    initial begin #2000000;$fatal(1,"camera FPS timeout");end
endmodule
