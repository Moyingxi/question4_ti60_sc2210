`timescale 1ns/1ps
// Complete, validated RAW captures committed to DDR, independent of playback.
// Source count changes by one; registered Gray crosses to the pixel domain.
module v9_camera_fps #(parameter CLK_HZ=148500000)(
    input source_clk,source_rst_n,input [31:0] captured,
    input clk,rst_n,output reg [11:0] fps_bcd
);
    reg [9:0] source_gray;
    (* async_reg="true" *) reg [9:0] gray_meta,gray_sync;
    wire [9:0] count;
    genvar g;
    generate for(g=0;g<10;g=g+1) begin:decode
        assign count[g]=^gray_sync[9:g];
    end endgenerate
    always @(posedge source_clk or negedge source_rst_n)
        if(!source_rst_n) source_gray<=0;
        else source_gray<=captured[9:0]^(captured[9:0]>>1);
    localparam TIMER_BITS=CLK_HZ>1?$clog2(CLK_HZ):1;
    reg [TIMER_BITS-1:0] ticks;
    reg [9:0] previous,binary;
    reg [11:0] work_bcd;
    reg [3:0] remaining;
    reg [11:0] adjusted;
    wire [9:0] delta=count-previous;
    always @* begin
        adjusted=work_bcd;
        if(work_bcd[3:0]>=5) adjusted[3:0]=work_bcd[3:0]+4'd3;
        if(work_bcd[7:4]>=5) adjusted[7:4]=work_bcd[7:4]+4'd3;
        if(work_bcd[11:8]>=5) adjusted[11:8]=work_bcd[11:8]+4'd3;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            gray_meta<=0;gray_sync<=0;ticks<=0;previous<=0;
            binary<=0;work_bcd<=0;remaining<=0;fps_bcd<=0;
        end else begin
            gray_meta<=source_gray;gray_sync<=gray_meta;
            if(ticks==CLK_HZ-1) begin
                ticks<=0;previous<=count;binary<=delta;work_bcd<=0;
                if(delta>999) begin fps_bcd<=12'h999;remaining<=0;end
                else remaining<=10;
            end else ticks<=ticks+1'b1;
            if(remaining!=0) begin
                work_bcd<={adjusted[10:0],binary[9]};binary<={binary[8:0],1'b0};
                remaining<=remaining-1'b1;
                if(remaining==1) fps_bcd<={adjusted[10:0],binary[9]};
            end
        end
    end
endmodule
