`timescale 1ns / 1ps

// 矩阵功能译码：采用实物行列位置，不依赖键帽字符；其余11键保留。
// R1C1冻结/继续，R1C2回放/退出，R1C3中值切换，R2C1阈值减，R2C2阈值加。
module matrix_controls #(
    parameter COLUMN_CYCLES = 24000,
    parameter RELEASE_CYCLES = 960,
    parameter DEBOUNCE_SCANS = 16
) (
    input             clk,                 // 输入：96MHz时钟
    input             rst_n,               // 输入：低有效复位
    input      [3:0]  key_row,             // 输入：四个异步行电平
    output     [3:0]  col_oe,              // 输出：四列拉低使能
    output            freeze_press,        // 输出：冻结/继续单拍请求
    output            replay_press,        // 输出：回放/退出单拍请求
    output            median_press,        // 输出：中值切换单拍请求
    output            minus_press,         // 输出：阈值减少单拍请求
    output            plus_press,          // 输出：阈值增加单拍请求
    output     [15:0] pressed,             // 输出：消抖后的单拍键位
    output     [15:0] stable_keys,         // 输出：稳定矩阵，供调试
    output            multi_key,           // 输出：多键状态
    output            armed                // 输出：释放确认状态
);
    matrix_keypad #(
        .COLUMN_CYCLES(COLUMN_CYCLES), .RELEASE_CYCLES(RELEASE_CYCLES),
        .DEBOUNCE_SCANS(DEBOUNCE_SCANS)
    ) scanner (
        .clk(clk), .rst_n(rst_n), .key_row(key_row), .col_oe(col_oe),
        .pressed(pressed), .stable_keys(stable_keys), .multi_key(multi_key), .armed(armed)
    );
    assign freeze_press = pressed[0];
    assign replay_press = pressed[1];
    assign median_press = pressed[2];
    assign minus_press = pressed[4];
    assign plus_press = pressed[5];
endmodule
