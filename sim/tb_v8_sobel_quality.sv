`timescale 1ns/1ps
// Complete Sobel pipeline: deterministic noise/contours, random input gaps and
// output stalls, changing external controls mid-frame, exact gray/RGB alignment.
module tb_v8_sobel_quality;
    localparam W=192,H=128,N=W*H;
    reg clk=0,rst_n=0;always #3.367 clk=~clk;
    reg start=0,canny=0,median_enable=1;
    reg [10:0] low=0,high=20;
    reg [7:0] raw_data=0;reg raw_valid=0;wire raw_ready;
    wire [31:0] pixel;wire valid,last,busy;reg ready=0;
    v8_frontend #(W,H) dut(clk,rst_n,start,canny,median_enable,low,high,
        raw_data,raw_valid,raw_ready,pixel,valid,ready,last,busy,1'b0,,,
        {1'b0,12'd256,12'd256,12'd256},,,);
    reg [31:0] raw[0:N-1],golden[0:N-1];
    reg [31:0] rng=32'h8a201024;
    integer f,sent,received,cycles;reg took,held=0;
    reg [31:0] held_pixel;reg held_last;
    always @(posedge clk) if(rst_n) begin
        if(held && (!valid || pixel!==held_pixel || last!==held_last))
            $fatal(1,"Sobel output changed during backpressure");
        held=valid && !ready;held_pixel=pixel;held_last=last;
    end
    initial begin
        repeat(8) @(negedge clk);rst_n=1;
        for(f=0;f<6;f=f+1) begin
            $readmemh($sformatf("sim/v8_sobel_raw%0d.hex",f),raw);
            $readmemh($sformatf("sim/v8_sobel_prep%0d.hex",f),golden);
            sent=0;received=0;cycles=0;
            canny=0;median_enable=f!=5;high=20;low=0;start=1;
            @(negedge clk);start=0;
            while(received<N) begin
                rng=(rng<<1)^({32{rng[31]}}&32'h04c11db7);
                ready=rng[0] || rng[4];
                if(!raw_valid && sent<N && (rng[1] || rng[5])) begin
                    raw_valid=1;raw_data=raw[sent][7:0];
                end
                // Frame-latched configuration must not follow these changes.
                if(sent>N/2) begin canny=1;median_enable=~(f!=5);high=120;end
                @(posedge clk);
                took=raw_valid && raw_ready;
                if(took)sent=sent+1;
                if(valid && ready) begin
                    if(pixel!==golden[received])
                        $fatal(1,"Sobel f%0d pixel%0d got%h expected%h",f,received,pixel,golden[received]);
                    if(last!==(received==N-1))$fatal(1,"Sobel last misalignment");
                    received=received+1;
                end
                @(negedge clk);if(took)raw_valid=0;
                cycles=cycles+1;
                if(cycles>N*30)$fatal(1,"Sobel timeout sent%0d received%0d",sent,received);
            end
            raw_valid=0;ready=1;
            repeat(8) @(negedge clk);
            if(sent!=N || busy || valid)$fatal(1,"Sobel frame failed to drain");
        end
        $display("PASS V8 Sobel six controlled scenes, input gaps, output stalls, frame-latched controls and exact image metadata");
        $finish;
    end
endmodule
