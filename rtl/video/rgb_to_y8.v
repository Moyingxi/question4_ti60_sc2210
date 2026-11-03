`timescale 1ns / 1ps

// ============================================================================
// RGB888 转灰度：Y=(77R+150G+29B+128)>>8，三级有效信号对齐。
// 常数乘法完全使用移位加法，无除法器；CE 为低时冻结整个流水线。
// ============================================================================
module rgb_to_y8 (
    input             clk,                                                  // 输入：本模块工作时钟
    input             rst_n,                                                // 输入：低有效复位
    input             ce,                                                   // 输入：流水线总时钟使能，低时冻结
    input             s_valid,                                              // 输入：输入数据有效
    input      [23:0] rgb,                                                  // 输入：RGB888 像素数据
    output reg        m_valid,                                              // 输出：输出数据有效
    output reg [ 7:0] y                                                     // 输出：输出 8 位灰度
);
    reg         v1;                                                         // 内部 reg：第一级、第二级有效标志
    reg         v2;                                                         // 内部 reg：第一级、第二级有效标志
    reg  [15:0] r77;                                                        // 内部 reg：红色乘 77 的寄存结果
    reg  [15:0] g150;                                                       // 内部 reg：绿色乘 150 的寄存结果
    reg  [15:0] b29;                                                        // 内部 reg：蓝色乘 29 的寄存结果
    reg  [15:0] rg;                                                         // 内部 reg：红绿加权和寄存器
    reg  [15:0] bdelay;                                                     // 内部 reg：蓝色加权项延迟对齐
    wire [15:0] r = {8'b0, rgb[23:16]};                                     // 内部 wire：RGB 通道零扩展至 16 位
    wire [15:0] g = {8'b0, rgb[15:8]};                                      // 内部 wire：RGB 通道零扩展至 16 位
    wire [15:0] b = {8'b0, rgb[7:0]};                                       // 内部 wire：RGB 通道零扩展至 16 位
    wire [15:0] sum = rg + bdelay + 16'd128;                                // 内部 wire：加权总和加 128 用于四舍五入

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            v1      <= 0;
            v2      <= 0;
            m_valid <= 0;
        end

        else if (ce) begin
            v1      <= s_valid;
            v2      <= v1;
            m_valid <= v2;
            r77     <= (r << 6) + (r << 3) + (r << 2) + r;
            g150    <= (g << 7) + (g << 4) + (g << 2) + (g << 1);
            b29     <= (b << 4) + (b << 3) + (b << 2) + b;
            rg      <= r77 + g150;
            bdelay  <= b29;
            y       <= sum[15:8];
        end
endmodule
