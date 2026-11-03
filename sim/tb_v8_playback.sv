`timescale 1ns/1ps
module tb_v8_playback;
    localparam HF=232;
    reg clk=0,rst_n=0;always #5 clk=~clk;
    reg freeze=0,replay=0,compare=0,select_b=0,prev=0,next=0,boundary=0,available=1,start=0,finish=0,success=1;
    wire record_frame,record_busy,view_history,hold_live,view_compare,waiting,selected_b;
    wire [8:0] slot,count,view_a,view_b,remaining,index_a,index_b;wire [1:0] mode;
    v8_playback_control #(HF) dut(clk,rst_n,freeze,replay,compare,select_b,prev,next,boundary,
        available,start,finish,success,record_frame,slot,record_busy,count,mode,
        view_history,hold_live,view_compare,view_a,view_b,remaining,waiting,selected_b,index_a,index_b);
    task tick; @(negedge clk);endtask
    task frame; boundary=1;tick();boundary=0;tick();endtask
    task record(input bit ok);
        if(!record_frame) $fatal(1,"unexpected record inhibit");
        start=1;tick();start=0;tick();success=ok;finish=1;tick();finish=0;tick();
    endtask
    initial begin
        repeat(4) tick();rst_n=1;tick();
        compare=1;tick();compare=0;frame();
        if(view_compare || view_history || count) $fatal(1,"empty compare");
        repeat(HF) record(1);
        if(count!=HF || slot!=0) $fatal(1,"full 232-frame history");
        start=1;tick();start=0;tick();
        if(count!=HF-1 || !record_busy) $fatal(1,"reservation drops overwritten frame");
        compare=1;tick();compare=0;frame();
        if(view_compare || record_frame) $fatal(1,"wait in-flight history");
        success=1;finish=1;tick();finish=0;tick();frame();
        if(!view_compare || record_frame || view_a!=1 || view_b!=0 || index_a!=0 || index_b!=HF-1)
            $fatal(1,"A/B oldest/newest ring %0d %0d",view_a,view_b);
        next=1;tick();next=0;frame();if(index_a!=1 || view_a!=2) $fatal(1,"advance A");
        select_b=1;tick();select_b=0;prev=1;tick();prev=0;frame();
        if(!selected_b || index_b!=HF-2 || view_b!=HF-1) $fatal(1,"select/previous B");
        prev=1;repeat(HF+2) tick();prev=0;frame();if(index_b!=0 || view_b!=1) $fatal(1,"saturate B");
        prev=1;next=1;tick();prev=0;next=0;frame();if(index_b!=0) $fatal(1,"opposite selectors");
        freeze=1;tick();freeze=0;frame();if(!view_compare) $fatal(1,"freeze should not exit compare");
        replay=1;tick();replay=0;frame();if(view_compare || mode!=2 || view_a!=1) $fatal(1,"compare->replay");
        freeze=1;tick();freeze=0;frame();if(mode!=3) $fatal(1,"pause");
        frame();frame();if(view_a!=1) $fatal(1,"pause drift");
        freeze=1;tick();freeze=0;frame();if(mode!=2 || view_a!=1) $fatal(1,"resume retains frame");
        frame();if(view_a!=2) $fatal(1,"replay order");repeat(HF-1) frame();
        if(mode!=0 || !record_frame) $fatal(1,"auto return");
        freeze=1;tick();freeze=0;frame();if(mode!=1 || !record_frame) $fatal(1,"live freeze still records");
        record(0);if(count!=HF-1) $fatal(1,"failed overwrite must remove old frame");
        compare=1;tick();compare=0;frame();if(!view_compare || index_b!=HF-2) $fatal(1,"partial history");
        compare=1;tick();compare=0;frame();if(mode!=0 || view_compare) $fatal(1,"exit compare");
        $display("PASS V8 232-frame A/B ring wrap/selection, write-drain lock, failed overwrite, replay/pause/exit");$finish;
    end
endmodule
