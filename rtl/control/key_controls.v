`timescale 1ns / 1ps

// ============================================================================
// 低有效按键消抖：两级同步，稳定 CYCLES 周期后更新状态。
// 仅在确认按下时输出一个时钟周期脉冲，长按不会重复触发。
// ============================================================================
module key_debounce #(
    parameter CYCLES = 1440000
) (
    input      clk,                                                         // 输入：本模块工作时钟
    input      rst_n,                                                       // 输入：低有效复位
    input      key_n,                                                       // 输入：低有效按键输入
    output reg pressed                                                      // 输出：消抖后的单周期按下脉冲
);
    (* async_reg="true" *) reg [                 1:0] sync = 3;             // 内部 reg：按键异步输入两级同步
    reg                        stable = 1;                                  // 内部 reg：已确认的稳定按键电平
    reg [$clog2(CYCLES+1)-1:0] count = 0;                                   // 内部 reg：输入变化后的稳定时长计数
    // 同步和消抖：仅接受持续稳定的按键状态变化。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync    <= 3;
            stable  <= 1;
            count   <= 0;
            pressed <= 0;
        end
        else begin
            sync    <= {sync[0], key_n};
            pressed <= 0;
            if (sync[1] == stable) count <= 0;

            else if (count == CYCLES - 1) begin
                count   <= 0;
                stable  <= sync[1];
                pressed <= !sync[1];
            end
            else count <= count + 1'b1;
        end
    end
endmodule

// ============================================================================
// 按键控制：26 档非线性阈值，0～50 步进 5，50～150 步进 10，150～250 步进 20。
// 通过档位索引查表；默认索引 18（第 19 档），阈值 130。
// 加减同时按下不调整；中值滤波按键独立切换，上电默认启用。
// ============================================================================
module key_controls #(
    parameter DEBOUNCE_CYCLES = 1440000
) (
    input             clk,                                                  // 输入：本模块工作时钟
    input             rst_n,                                                // 输入：低有效复位
    input             key_plus_n,                                           // 输入：低有效按键输入
    input             key_minus_n,                                          // 输入：低有效按键输入
    input             key_median_n,                                         // 输入：兼容原消抖测试；V3顶层固定为1，不接物理引脚
    output reg [10:0] threshold = 130,                                      // 输出：边缘判决阈值
    output reg        median_enable = 1,                                    // 输出：中值滤波使能，高有效
    input             matrix_plus_press,                                   // 输入：矩阵阈值增加单拍脉冲
    input             matrix_minus_press,                                  // 输入：矩阵阈值减少单拍脉冲
    input             matrix_median_press                                  // 输入：矩阵中值切换单拍脉冲
);
    wire plus;                                                              // 内部 wire：阈值增加脉冲
    wire minus;                                                             // 内部 wire：阈值减小脉冲
    wire toggle;                                                            // 内部 wire：中值旁路切换脉冲
    // 板载与矩阵同方向同拍合并一次；相反方向同拍保持阈值。
    wire plus_event = plus | matrix_plus_press;
    wire minus_event = minus | matrix_minus_press;
    wire median_event = toggle | matrix_median_press;
    reg [4:0] level_index = 5'd18;                                           // 内部 reg：阈值档位索引，合法值 0～25

    // 索引与阈值一一对应，使跨分段边界的加减操作严格互逆。
    function [10:0] threshold_lut;
        input [4:0] index;                                                  // 输入：目标档位索引
        begin
            case (index)
                5'd0:  threshold_lut = 11'd0;
                5'd1:  threshold_lut = 11'd5;
                5'd2:  threshold_lut = 11'd10;
                5'd3:  threshold_lut = 11'd15;
                5'd4:  threshold_lut = 11'd20;
                5'd5:  threshold_lut = 11'd25;
                5'd6:  threshold_lut = 11'd30;
                5'd7:  threshold_lut = 11'd35;
                5'd8:  threshold_lut = 11'd40;
                5'd9:  threshold_lut = 11'd45;
                5'd10: threshold_lut = 11'd50;
                5'd11: threshold_lut = 11'd60;
                5'd12: threshold_lut = 11'd70;
                5'd13: threshold_lut = 11'd80;
                5'd14: threshold_lut = 11'd90;
                5'd15: threshold_lut = 11'd100;
                5'd16: threshold_lut = 11'd110;
                5'd17: threshold_lut = 11'd120;
                5'd18: threshold_lut = 11'd130;
                5'd19: threshold_lut = 11'd140;
                5'd20: threshold_lut = 11'd150;
                5'd21: threshold_lut = 11'd170;
                5'd22: threshold_lut = 11'd190;
                5'd23: threshold_lut = 11'd210;
                5'd24: threshold_lut = 11'd230;
                5'd25: threshold_lut = 11'd250;
                default: threshold_lut = 11'd130;
            endcase
        end
    endfunction

    key_debounce #(DEBOUNCE_CYCLES) a (
        clk,
        rst_n,
        key_plus_n,
        plus
    );

    key_debounce #(DEBOUNCE_CYCLES) b (
        clk,
        rst_n,
        key_minus_n,
        minus
    );

    key_debounce #(DEBOUNCE_CYCLES) c (
        clk,
        rst_n,
        key_median_n,
        toggle
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            threshold     <= 130;
            level_index   <= 5'd18;
            median_enable <= 1;
        end
        else begin
            // 每次按键只移动一档；阈值与索引同拍更新，首末档饱和。
            if (plus_event && !minus_event && level_index < 5'd25) begin
                level_index <= level_index + 5'd1;
                threshold   <= threshold_lut(level_index + 5'd1);
            end
            if (minus_event && !plus_event && level_index > 5'd0) begin
                level_index <= level_index - 5'd1;
                threshold   <= threshold_lut(level_index - 5'd1);
            end
            if (median_event) median_enable <= !median_enable;
        end
    end
endmodule
