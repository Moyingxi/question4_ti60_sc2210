`timescale 1ns/1ps
module tb_v8_processor;
    parameter W=64,H=48,FULL=0,CHAIN=1,BIDIR=1,FAST=0,CAP=8192;
    localparam DIR=FULL?"sim/full/":"sim/";
    localparam N=W*H;
    reg clk=0,rst_n=0;always #3.367 clk=~clk;
    reg [25:0] command=0;reg cv=0;wire cr;
    reg [127:0] input_word=0;reg iv=0;wire ir;
    wire [127:0] output_word;wire ov;reg ready=0;wire done,busy;
    v8_processor_io #(W,H,CAP) dut(clk,rst_n,command,cv,cr,input_word,iv,ir,output_word,ov,ready,done,busy,1'b0,,,{1'b0,12'd256,12'd256,12'd256},,,);
    reg [31:0] pixels[0:N-1],results[0:N-1],golden[0:N-1],raw[0:N-1],prep[0:N-1];
    integer sent,received,cycles,k,f,p,rounds;reg changes;
    reg use_fast;
    reg [127:0] fast_words[0:N*3/16-1];
    reg [31:0] rng=32'h87281942;
    function [31:0] random_next(input [31:0] s);
        reg [31:0] t;begin t=s^(s<<13);t=t^(t>>17);random_next=t^(t<<5);end
    endfunction
    task run_stage(input integer stage,input integer frame);
        integer nin,nout,ipix,opix,j;
        begin
            nin=stage<2?N/16:(use_fast?N*3/16:N/4);nout=(stage==0 || stage==3)?N/16:(use_fast?N*3/16:N/4);
            sent=0;received=0;cycles=0;
            @(negedge clk);while(!cr) @(negedge clk);
            command={use_fast,stage[1:0],!frame[0],11'd60,11'd130};cv=1;
            @(negedge clk);cv=0;
            while(received<nout) begin
                rng=random_next(rng);ready=rng[0] || rng[2];
                if(!iv && sent<nin && rng[3]) begin
                    iv=1;
                    for(j=0;j<(stage<2?16:4);j=j+1) begin
                        if(stage<2) input_word[j*8+:8]=raw[sent*16+j][7:0];
                        else input_word[j*32+:32]=pixels[sent*4+j];
                        if(use_fast && stage==3) input_word=fast_words[sent];
                    end
                end
                @(posedge clk);
                if(iv && ir) sent=sent+1;
                if(ov && ready) begin
                    if(use_fast && stage==1) fast_words[received]=output_word;
                    else for(j=0;j<4;j=j+1) results[received*4+j]=output_word[j*32+:32];
                    received=received+1;
                end
                if(iv && ir) begin @(negedge clk);iv=0;end
                else @(negedge clk);
                cycles=cycles+1;if(cycles>N*100) $fatal(1,"stage timeout %0d sent=%0d recv=%0d",stage,sent,received);
            end
            iv=0;ready=1;
            if(sent!=nin) $fatal(1,"wrong input count %0d/%0d",sent,nin);
            repeat(8) @(negedge clk);
            if(busy || ov) $fatal(1,"stage did not drain");
        end
    endtask
    task converge;
        integer i;
        reg [31:0] swap_pixel;
        begin
            changes=1;rounds=0;
            while(changes) begin
                if(BIDIR && rounds[0]) for(i=0;i<N/2;i=i+1) begin
                    swap_pixel=pixels[i];pixels[i]=pixels[N-1-i];pixels[N-1-i]=swap_pixel;
                end
                run_stage(2,0);
                if(BIDIR && rounds[0]) for(i=0;i<N/2;i=i+1) begin
                    swap_pixel=results[i];results[i]=results[N-1-i];results[N-1-i]=swap_pixel;
                end
                changes=0;rounds=rounds+1;
                for(p=0;p<N;p=p+1) begin changes=changes|results[p][26];pixels[p]=results[p];end
                if(rounds>N) $fatal(1,"hysteresis failed to converge");
            end
        end
    endtask
    initial begin
        repeat(8) @(negedge clk);rst_n=1;
        for(f=0;f<4;f=f+1) begin
            $readmemh($sformatf("%sv8_raw%0d.hex",DIR,f),raw);
            $readmemh($sformatf("%sv8_prep%0d.hex",DIR,f),prep);
            $readmemh($sformatf("%sv8_final%0d.hex",DIR,f),golden,0,N/4-1);
            use_fast=FAST && f>=2;
            run_stage(f<2?0:1,f);
            if(use_fast && fast_words[N*3/16-1][127]) begin use_fast=0;run_stage(1,f);end
            if(f>=2 && !use_fast) begin
                for(p=0;p<N;p=p+1) begin
                    if(results[p]!==prep[p]) $fatal(1,"prep f%0d pixel%0d got%h expected%h",f,p,results[p],prep[p]);
                    pixels[p]=results[p];
                end
                converge();
            end
            if(f>=2) begin run_stage(3,f);
            end
            for(p=0;p<N/4;p=p+1)
                if(results[p]!==golden[p]) $fatal(1,"final f%0d pixel%0d got%h expected%h",f,p,results[p],golden[p]);
            $display("Verified %0dx%0d frame %0d",W,H,f);
        end
        if(CHAIN) begin use_fast=0;
        $readmemh("sim/v8_chain.hex",pixels);$readmemh("sim/v8_chain_final.hex",golden);
        converge();
        if(BIDIR && rounds>20) $fatal(1,"bidirectional sweep performance regression %0d",rounds);
        for(p=0;p<N;p=p+1) if((results[p]&32'h03ffffff)!==golden[p]) $fatal(1,"BFS mismatch %0d",p);
        $display("PASS V8 long weak-chain propagation %0d rounds matches independent BFS",rounds);
        run_stage(3,0);$readmemh("sim/v8_chain_scaled.hex",golden,0,N/4-1);
        for(p=0;p<N/4;p=p+1) if(results[p]!==golden[p]) $fatal(1,"chain scale %0d",p);
        end
        $display("PASS V8 processor RAW/Bayer/gray/median/Gaussian/Sobel/NMS/hysteresis/RGB565/scale with stalls");$finish;
    end
endmodule
