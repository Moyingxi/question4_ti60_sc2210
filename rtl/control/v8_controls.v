`timescale 1ns/1ps
// V8 参数按键。显示开关独立；Sobel/Canny各自保留阈值，不在帧内改变算法。
// R1C4=彩色，R2C3=高/低阈值选择，R2C4=算法，R4C1=红边，R4C2=比较灰度/彩色/边缘。
module v8_controls #(parameter DEBOUNCE_CYCLES=1440000)(
    input clk,rst_n,key_plus_n,key_minus_n,input [15:0] pressed,
    output [10:0] threshold_high,threshold_low,
    output reg median_enable,canny_enable,color_enable,overlay_enable,
    output reg [1:0] compare_view, // 0灰度、1彩色、2二值边缘；两侧同步，独立于实时开关
    output reg select_low,
    output reg [2:0] shape_control, // [0] enable; [2:1] contour sensitivity
    output [31:0] telemetry // low 16: select_low, low/high/Sobel indices
);
    wire plus,minus;
    key_debounce #(DEBOUNCE_CYCLES) a(clk,rst_n,key_plus_n,plus);
    key_debounce #(DEBOUNCE_CYCLES) b(clk,rst_n,key_minus_n,minus);
    wire up=plus | pressed[5],down=minus | pressed[4];
    reg [4:0] sobel_index,low_index,high_index;
    assign telemetry={16'd0,select_low,low_index,high_index,sobel_index};
    function [10:0] lut(input [4:0] n);
        begin
            if(n<=10) lut=n*11'd5;
            else if(n<=20) lut=11'd50+(n-10)*11'd10;
            else lut=11'd150+(n-20)*11'd20;
        end
    endfunction
    assign threshold_high=lut(canny_enable?high_index:sobel_index);
    assign threshold_low=lut(low_index);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            // User's board settings recovered before reload: Sobel20, Canny20/0.
            sobel_index<=4;high_index<=4;low_index<=0;median_enable<=1;
            canny_enable<=0;color_enable<=0;overlay_enable<=0;compare_view<=0;select_low<=0;shape_control<=3'b011;
        end else begin
            if(pressed[2]) median_enable<=!median_enable;
            if(pressed[3]) color_enable<=!color_enable;
            if(pressed[6]) select_low<=!select_low;
            if(pressed[7]) canny_enable<=!canny_enable;
            if(pressed[12]) overlay_enable<=!overlay_enable;
            if(pressed[13]) compare_view<=compare_view==2?2'd0:compare_view+2'd1;
            if(pressed[14]) shape_control[0]<=!shape_control[0];
            if(pressed[15]) shape_control[2:1]<=shape_control[2:1]+2'd1;
            if(up != down) begin
                if(!canny_enable) begin
                    if(up && sobel_index<25) sobel_index<=sobel_index+1'b1;
                    if(down && sobel_index>0) sobel_index<=sobel_index-1'b1;
                end else if(select_low) begin
                    if(up && low_index+1<high_index) low_index<=low_index+1'b1;
                    if(down && low_index>0) low_index<=low_index-1'b1;
                end else begin
                    if(up && high_index<25) high_index<=high_index+1'b1;
                    if(down && high_index>low_index+1) high_index<=high_index-1'b1;
                end
            end
        end
    end
endmodule
