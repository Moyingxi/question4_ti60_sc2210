`timescale 1ns/1ps
module tb_v8_controls;
    reg clk=0,rst_n=0,kp=1,km=1;always #5 clk=~clk;
    reg [15:0] pressed=0;
    wire [10:0] high,low;wire median,canny,color,overlay,select_low;wire [1:0] compare_view;wire [2:0] shape_control;
    wire [31:0] telemetry;
    v8_controls #(4) dut(clk,rst_n,kp,km,pressed,high,low,median,canny,color,overlay,compare_view,select_low,shape_control,telemetry);
    integer k;
    task click(input integer key);
        @(negedge clk);pressed=16'h1<<key;@(negedge clk);pressed=0;
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        if(high!==20 || low!==0 || !median || canny || color || overlay) $fatal(1,"defaults");
        if(shape_control!==3'b011) $fatal(1,"shape defaults");
        click(14);if(shape_control!==3'b010) $fatal(1,"shape toggle off");
        click(15);if(shape_control!==3'b100) $fatal(1,"shape threshold while off");
        click(14);if(shape_control!==3'b101) $fatal(1,"shape toggle on");
        click(15);click(15);click(15);if(shape_control!==3'b011) $fatal(1,"shape threshold wrap");
        click(3);if(!color || overlay) $fatal(1,"independent color");
        click(12);if(!color || !overlay) $fatal(1,"independent overlay");
        if(shape_control!==3'b011) $fatal(1,"shape defaults");
        click(14);if(shape_control!==3'b010) $fatal(1,"shape toggle off");
        click(15);if(shape_control!==3'b100) $fatal(1,"shape threshold while off");
        click(14);if(shape_control!==3'b101) $fatal(1,"shape toggle on");
        click(15);click(15);click(15);if(shape_control!==3'b011) $fatal(1,"shape threshold wrap");
        click(3);if(color || !overlay) $fatal(1,"gray red overlay");
        if(compare_view!==0) $fatal(1,"default comparison gray");
        repeat(3) begin
            click(13);if(compare_view!==1 || color || !overlay) $fatal(1,"comparison color, live independent");
            click(13);if(compare_view!==2) $fatal(1,"comparison edges");
            click(13);if(compare_view!==0) $fatal(1,"comparison gray wrap");
        end
        click(2);if(median) $fatal(1,"median");
        for(k=0;k<30;k=k+1) click(4);
        if(high!=0) $fatal(1,"low saturation");
        for(k=0;k<25;k=k+1) begin
            click(5);
            if(high!=(k<10?(k+1)*5:k<20?50+(k-9)*10:150+(k-19)*20)) $fatal(1,"26 levels %0d",k);
        end
        click(5);if(high!=250) $fatal(1,"high saturation");
        @(negedge clk);pressed=16'h30;@(negedge clk);pressed=0;
        if(high!=250) $fatal(1,"opposite events");
        click(7);if(!canny || high!=20 || low!=0) $fatal(1,"separate Canny parameters");
        for(k=0;k<40;k=k+1) click(4);
        if(high!=5 || low!=0) $fatal(1,"high crossed low");
        click(5);click(5);click(5);
        click(6);for(k=0;k<40;k=k+1) click(5);
        if(low!=15 || high!=20) $fatal(1,"low crossed high");
        for(k=0;k<40;k=k+1) click(4);
        if(low!=0) $fatal(1,"low minimum");
        kp=0;repeat(25) @(negedge clk);if(low!=5) $fatal(1,"board plus/hold");
        kp=1;repeat(12) @(negedge clk);km=0;repeat(25) @(negedge clk);
        if(low!=0) $fatal(1,"board minus");
        click(7);if(high!=250) $fatal(1,"Sobel retained");
        click(14);click(15);if(high!=250 || canny) $fatal(1,"reserved keys");
        $display("PASS V8 26 thresholds, low<high, board buttons, independent color/red overlay and mode controls");$finish;
    end
endmodule
