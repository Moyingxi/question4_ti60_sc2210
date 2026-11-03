`timescale 1ns/1ps
`include "sim/v8_shapes_cases.vh"
module tb_v8_shapes #(parameter FIRST_CASE=0,LAST_CASE=`V8_SHAPE_CASES);
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,fs=0,fe=0,sv=0,sd=0;
    wire [227:0] boxes;wire valid,overflow,busy;wire [31:0] completed;wire [21:0] cycles;
    wire [9:0] diagnostics;
    v8_shape_detector dut(clk,rst_n,fs,fe,sv,sd,boxes,valid,overflow,busy,completed,cycles,diagnostics);
    reg masks[0:129600*`V8_SHAPE_CASES-1];reg [227:0] expected[0:`V8_SHAPE_CASES-1];
    integer f,i,waits,xx,yy;
    always @(posedge clk)if(rst_n && FIRST_CASE==46 && dut.state==31)
        $display("raw geometry count=%0d maxstep=%0d radial=%0d..%0d size=%0d,%0d",dut.corner_count,dut.max_support_step,dut.min_r2,dut.max_r2,dut.bw,dut.bh);
    always @(posedge clk) if(rst_n && f>=FIRST_CASE && f<LAST_CASE) begin
        if(dut.state==3 && dut.mask_q!==masks[f*129600+dut.pixel_index])
            $fatal(1,"packed sequential read mismatch addr%0d word%0d bit%0d got%b exp%b",dut.pixel_index,dut.mask_word_address_q,dut.mask_bit_q,dut.mask_q,masks[f*129600+dut.pixel_index]);
        if((dut.state==38 || dut.state==54) && dut.mask_q!==masks[f*129600+dut.probe_address])
            $fatal(1,"packed random read mismatch state%0d addr%0d word%0d bit%0d",dut.state,dut.probe_address,dut.mask_word_address_q,dut.mask_bit_q);
    end
    task start_frame;begin @(negedge clk);fs=1;@(negedge clk);fs=0;end endtask
    task finish_frame;integer word_index,bit_index;reg [9:0] expected_word;begin @(negedge clk);sv=0;fe=1;
        @(negedge clk);fe=0;
        waits=0;while(busy && waits<5000000) begin @(negedge clk);waits=waits+1;end
        if(busy) $fatal(1,"shape processing hung");
    end endtask
    initial begin
        $readmemh("sim/v8_shapes_mask.hex",masks);$readmemh("sim/v8_shapes_expected.hex",expected);
        repeat(4) @(negedge clk);rst_n=1;
        for(f=FIRST_CASE;f<LAST_CASE;f=f+1) begin
            start_frame();
            for(i=0;i<129600;i=i+1) begin @(negedge clk);sv=1;sd=masks[f*129600+i];end
            finish_frame();
            if(!valid || overflow || boxes!==expected[f])begin
                $display("debug corners=%0d size=%0d,%0d tol=%0d probes=%0d dot=%0d length=%0d bias=%0d,%0d",dut.corner_count,dut.bw,dut.bh,dut.tolerance,dut.good_probes,dut.abs_dot,dut.len_product,dut.center_bias_x,dut.center_bias_y);
                for(xx=0;xx<dut.corner_count;xx=xx+1)$display("corner %0d %0d,%0d",xx,dut.corners[xx][8:0],dut.corners[xx][17:9]);
                $fatal(1,"case %0d boxes=%h expected=%h valid=%b overflow=%b",f,boxes,expected[f],valid,overflow);
            end
            if(f==9 && dut.stat_value[305:288]!=18'd129600)$fatal(1,"18-bit full-frame count truncated");
            $display("case %0d cycles %0d boxes %h",f,cycles,boxes);
        end
        start_frame();
        for(i=0;i<129600;i=i+1) begin
            @(negedge clk);sv=1;xx=i%480;yy=i/480;sd=(xx%10<2)&&(yy%10==0);
        end
        finish_frame();if(valid || !overflow || boxes!=0 || diagnostics[9:8]!=1 || diagnostics[7:0]!=255) $fatal(1,"label overflow not rejected/diagnosed");
        start_frame();
        for(i=0;i<129600;i=i+1) begin
            @(negedge clk);sv=1;xx=i%480;yy=i/480;sd=(xx%10<2)&&(yy%10<2);
        end
        finish_frame();if(valid || !overflow || boxes!=0 || diagnostics[9:8]!=1)$fatal(1,"2x2 component label exhaustion hidden");
        start_frame();repeat(17) begin @(negedge clk);sv=1;sd=0;end
        finish_frame();if(valid || boxes!=0 || diagnostics[9:8]!=3) $fatal(1,"incomplete frame retained old boxes/not diagnosed");
        start_frame();for(i=0;i<129600;i=i+1) begin @(negedge clk);sv=1;sd=1;end
        @(negedge clk);sv=0;fe=1;@(negedge clk);fe=0;
        repeat(20) @(negedge clk);
        dut.elapsed_cycles=22'h3ffffe;repeat(3)@(negedge clk);
        if(cycles!==22'h3fffff)$fatal(1,"22-bit cycle counter wrapped instead of saturating");
        start_frame();
        if(busy || valid || !overflow || boxes!=0 || diagnostics[9:8]!=2) $fatal(1,"deadline overrun not rejected/diagnosed");
        start_frame();
        for(i=0;i<129600;i=i+1) begin
            @(negedge clk);sv=1;xx=i%480;yy=i/480;sd=xx>=360 && xx<=376 && yy>=230 && yy<=246;
        end
        finish_frame();
        if(!valid || overflow || diagnostics[9:8]!=0 || boxes!={190'd0,2'd2,9'd246,9'd230,9'd376,9'd360})
            $fatal(1,"detector did not reacquire after faults without scene shaking");
        $display("PASS shape recognition: %0d analytic fixtures, rotated rectangles/triangles, contours, rejects, overflow, incomplete/deadline",LAST_CASE-FIRST_CASE);$finish;
    end
endmodule
