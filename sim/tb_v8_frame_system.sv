`timescale 1ns/1ps
// 真实处理器+异步FIFO+DDR调度器，内存模型在读写两端独立随机停顿。
module tb_v8_frame_system;
    parameter W=64,H=48,FULL=0,FAST=0,CAP=8192;
    localparam DIR=FULL?"sim/full/":"sim/";
    localparam N=W*H,RW=N/16,OW=N/16,ROW=W/8,HW=OW,SW=N/4,HF=4;
    reg clk=0,pclk=0,rst_n=0;always #5 clk=~clk;always #3.367 pclk=~pclk;
    reg [145:0] cap_data=0;reg cap_valid=0;wire cap_ready;
    wire [127:0] result_data,raw_in,raw_out,result_in;
    wire result_valid,result_ready,raw_iv,raw_ir,raw_ov,raw_or,result_iv,result_ir;
    wire [10:0] raw_level,result_level;
    wire [25:0] command,pcmd;wire cv,cr,pcv,pcr;
    wire [151:0] display;wire dv;reg dr=1;
    reg [9:0] line=0;reg lv=0;wire lr;
    reg [10:0] threshold=130,low=60;reg median=1,canny=0,color=0,overlay=0;reg [1:0] compare_view=0;
    reg freeze=0,replay=0,compare=0,select_b=0,prev=0,next=0;
    wire wreq,waccept,wvalid,wready,rreq,raccept,rvalid,rready;
    wire [31:0] wa,ra;wire [7:0] wl,rl;wire [127:0] wd,rd;
    reg wdone=0,rdone=0,werror=0,rerror=0;
    wire [31:0] captured,processed,discarded,errors,passes;wire [15:0] state;
    wire [1:0] mode;wire [8:0] count,remaining,ia,ib;
    wire hist_busy,waiting,cmp_active,selected;
    v8_frame_store #(HF,RW,OW,ROW,FAST) dut(
        clk,rst_n,1'b1,cap_data,cap_valid,cap_ready,12'd16,
        result_data,result_valid,result_ready,result_level,raw_in,raw_iv,raw_ir,raw_level,
        display,dv,dr,10'd0,line,lv,lr,command,cv,cr,threshold,median,
        wreq,wa,wl,waccept,wd,wvalid,wready,wdone,werror,
        rreq,ra,rl,raccept,rd,rvalid,rready,rdone,rerror,captured,processed,discarded,errors,state,
        freeze,replay,mode,count,remaining,hist_busy,waiting,canny,low,color,overlay,compare_view,
        compare,select_b,prev,next,cmp_active,selected,ia,ib,passes,);
    async_fifo #(128,10) rf(clk,rst_n,raw_in,raw_iv,raw_ir,raw_level,pclk,rst_n,raw_out,raw_ov,raw_or,);
    async_fifo #(128,10) of(pclk,rst_n,result_in,result_iv,result_ir,,clk,rst_n,result_data,result_valid,result_ready,result_level);
    async_fifo #(26,2) cf(clk,rst_n,command,cv,cr,,pclk,rst_n,pcmd,pcv,pcr,);
    v8_processor_io #(W,H,CAP) proc(pclk,rst_n,pcmd,pcv,pcr,raw_out,raw_ov,raw_or,result_in,result_iv,result_ir,,,1'b0,,,{1'b0,12'd256,12'd256,12'd256},,,);
    reg [127:0] mem[0:3*RW+3*OW+HF*HW+2*SW-1];
    function integer address(input [31:0] a);
        integer slot,offset;
        begin
            address=-1;
            if(a<32'h00c00000) begin slot=a>>22;offset=(a&32'h3fffff)>>4;if(slot<3 && offset<RW) address=slot*RW+offset;end
            else if(a>=32'h01000000 && a<32'h01600000) begin
                slot=(a-32'h01000000)>>21;offset=(a&32'h1fffff)>>4;if(offset<OW) address=3*RW+slot*OW+offset;
            end else if(a>=32'h02000000 && a<32'h02800000) begin
                slot=(a-32'h02000000)>>21;offset=(a&32'h1fffff)>>4;if(offset<HW) address=3*RW+3*OW+slot*HW+offset;
            end else if(a>=32'h1f000000 && a<32'h20000000) begin
                slot=(a-32'h1f000000)>>23;offset=(a&32'h7fffff)>>4;if(offset<SW) address=3*RW+3*OW+HF*HW+slot*SW+offset;
            end
            if(address<0) $fatal(1,"out of allocated frame address %h",a);
        end
    endfunction
    reg [31:0] rng=32'h81256736;
    always @(posedge clk) rng<=(rng<<1)^{32{rng[31]}}&32'h04c11db7;
    reg wb=0,rb=0,rv=0;reg [31:0] waddr,raddr;reg [7:0] wleft,rleft;reg [127:0] rdata;
    reg inject_history_error=0;
    assign waccept=wreq && !wb && rng[0];assign wready=wb && (rng[1] || rng[5]);
    assign raccept=rreq && !rb && rng[2];assign rvalid=rv;assign rd=rdata;
    always @(posedge clk) begin
        wdone<=0;rdone<=0;werror<=0;rerror<=0;
        if(waccept) begin wb<=1;waddr<=wa;wleft<=wl;end
        if(wvalid && wready) begin
            mem[address(waddr)]<=wd;waddr<=waddr+16;wleft<=wleft-1'b1;
            if(wleft==0) begin
                wb<=0;wdone<=1;
                if(inject_history_error && waddr>=32'h02000000 && waddr<32'h02800000) begin
                    werror<=1;inject_history_error<=0;
                end
            end
        end
        if(raccept) begin rb<=1;raddr<=ra;rleft<=rl;end
        if(rb && !rv && rng[3]) begin rdata<=mem[address(raddr)];rv<=1;end
        if(rv && rready) begin
            rv<=0;raddr<=raddr+16;rleft<=rleft-1'b1;
            if(rleft==0) begin rb<=0;rdone<=1;end
        end
    end
    reg [31:0] raw[0:N-1],golden[0:N/4-1];
    integer f,k,j,t,base,before_count,packets,expect_side;
    reg [31:0] expect_a[0:N/4-1],expect_b[0:N/4-1];
    task tick;@(negedge clk);endtask
    task capture(input integer frame);
        begin
            $readmemh($sformatf("%sv8_raw%0d.hex",DIR,frame),raw);
            for(k=0;k<RW;k=k+1) begin
                tick();cap_valid=1;cap_data={1'b0,k[16:0],128'd0};
                for(j=0;j<16;j=j+1) cap_data[j*8+:8]=raw[k*16+j][7:0];
                @(posedge clk);while(!cap_ready) @(posedge clk);
                tick();cap_valid=0;
            end
        end
    endtask
    task await_processed(input integer target);
        begin
            t=0;while(processed<target) begin tick();t=t+1;if(t>N*100) $fatal(1,"processing timeout phase%0d index%0d",dut.phase,dut.result_index);end
            repeat(8) tick();
        end
    endtask
    task read_line(input integer y,input integer historical,input integer comparing,input integer slot_a,input integer slot_b);
        integer n,x,index,maddr,halfword,side;reg [31:0] expixel;reg [127:0] word;
        begin
            packets=0;line=y;lv=1;
            @(posedge clk);while(!lr) @(posedge clk);tick();lv=0;
            while(dut.row_active || dut.rbusy) begin
                dr=rng[7] || rng[9];
                @(posedge clk);
                if(dv && dr) begin
                    side=packets/ROW;index=packets%ROW;
                    if(display[151]!=side || display[145:136]!=y || display[135:128]!=index)
                        $fatal(1,"display packet ordering %0d got%h",packets,display[151:128]);
                    if(display[149]!=comparing || display[148]!=historical) $fatal(1,"display flags");
                    if(comparing && (display[150]!=(compare_view==2) || display[146]!=(compare_view==1)))
                        $fatal(1,"comparison view flags");
                    for(n=0;n<4;n=n+1) begin
                        if(historical) begin
                            x=y*(W/2)+index*4+n;
                            maddr=3*RW+3*OW+(side?slot_b:slot_a)*HW+x/4;
                            word=mem[maddr];expixel=word[(x%4)*32+:32];
                            if(display[n*32+:32]!==expixel) $fatal(1,"history full color content y%0d side%0d index%0d",y,side,index);
                        end else begin
                            word=mem[3*RW+slot_a*OW+y*ROW+index];expixel=word[n*32+:32];
                            if(display[n*32+:32]!==expixel) $fatal(1,"display content y%0d side%0d index%0d",y,side,index);
                        end
                    end
                    packets=packets+1;
                end
                tick();
            end
            dr=1;if(packets!=ROW*(comparing?2:1)) $fatal(1,"display packets %0d",packets);
        end
    endtask
    initial begin
        repeat(12) tick();rst_n=1;repeat(12) tick();
        if(FULL) begin
            // 全尺寸重点覆盖19/20位地址计数、首末行、两种算法和32位完整历史。
            // 环回/故障组合已由同一套模块的小尺寸压力分支覆盖。
            for(f=0;f<2;f=f+1) begin
                canny=f!=0;median=f==0;capture(f==0?0:3);await_processed(f+1);
                $readmemh($sformatf("%sv8_final%0d.hex",DIR,f==0?0:3),golden);
                base=3*RW+dut.result_latest*OW;
                for(k=0;k<N/4;k=k+1) begin
                    if(mem[base+k/4][(k%4)*32+:32]!==golden[k]) $fatal(1,"1080p DDR final f%0d pixel%0d",f,k);
                    if(mem[3*RW+3*OW+f*HW+k/4][(k%4)*32+:32]!==golden[k]) $fatal(1,"1080p history pixel%0d",k);
                end
                read_line(0,0,0,dut.result_latest,0);read_line(H/2-1,0,0,dut.result_latest,0);
                $display("Verified 1920x1080 DDR %s and complete history",f==0?"Sobel":"Canny");
            end
            compare=1;tick();compare=0;read_line(0,1,1,0,1);read_line(H/2-1,1,1,0,1);
            compare_view=1;read_line(0,1,1,0,1);read_line(H/2-1,1,1,0,1);
            compare_view=2;read_line(0,1,1,0,1);read_line(H/2-1,1,1,0,1);
            compare_view=0;read_line(0,1,1,0,1);
            if(count!=2 || errors!=0 || (passes==0 && dut.fast_frames==0)) $fatal(1,"1080p counters");
            $display("PASS V8 full 1920x1080 DDR pipeline, all pixels, first/last rows, historical A/B");$finish;
        end
        for(f=0;f<4;f=f+1) begin
            canny=f>=2;median=!f[0];capture(f);await_processed(f+1);
            $readmemh($sformatf("%sv8_final%0d.hex",DIR,f),golden);
            base=3*RW+dut.result_latest*OW;
            for(k=0;k<N/4;k=k+1) begin
                if(mem[base+k/4][(k%4)*32+:32]!==golden[k]) $fatal(1,"DDR final f%0d pixel%0d",f,k);
                if(mem[3*RW+3*OW+f*HW+k/4][(k%4)*32+:32]!==golden[k]) $fatal(1,"history full pixel f%0d pixel%0d",f,k);
            end
            color=1;overlay=1;read_line(0,0,0,dut.result_latest,0);read_line(1,0,0,dut.result_latest,0);
            $display("Verified DDR full frame %0d, resolution %0dx%0d",f,W,H);
        end
        if(count!=4 || (passes==0 && dut.fast_frames==0) || errors!=0) $fatal(1,"capture/process/history counts");
        compare=1;tick();compare=0;read_line(0,1,1,0,3);read_line(1,1,1,0,3);
        compare_view=1;read_line(0,1,1,0,3);read_line(1,1,1,0,3);
        compare_view=2;read_line(0,1,1,0,3);read_line(1,1,1,0,3);
        compare_view=0;read_line(0,1,1,0,3);
        if(!cmp_active || hist_busy) $fatal(1,"compare lock");
        next=1;tick();next=0;read_line(0,1,1,1,3);
        select_b=1;tick();select_b=0;prev=1;tick();prev=0;read_line(0,1,1,1,2);
        // 比较期间采集/处理继续，但历史槽内容不变。
        canny=0;median=1;capture(0);await_processed(5);if(count!=4) $fatal(1,"history changed while comparing");
        read_line(0,1,1,1,2);
        compare=1;tick();compare=0;read_line(0,0,0,dut.result_latest,0);
        before_count=processed;inject_history_error=1;capture(0);
        wait(dut.processing);tick();
        t=0;while(hist_busy || dut.processing || captured<6) begin tick();t=t+1;if(t>N*100) $fatal(1,"error drain timeout");end
        repeat(40) tick();
        if(processed!=before_count || errors!=1 || count!=3) $fatal(1,"failed history was published processed%0d/%0d errors%0d history%0d",processed,before_count,errors,count);
        capture(0);await_processed(6);if(count!=4) $fatal(1,"failed history recovery");
        if(FAST && CAP==8 && dut.fallback_frames==0) $fatal(1,"forced overflow fallback not exercised");
        $display("PASS V8 DDR phases/Canny convergence/async FIFOs/full-color history/A-B three views/failure recovery");$finish;
    end
    initial begin #10000000000;$fatal(1,"global timeout");end
endmodule
