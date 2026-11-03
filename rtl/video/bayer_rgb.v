`timescale 1ns / 1ps

// ============================================================================
// Bayer 双线性插值：3×3 RAW8 窗口恢复 RGB888，四邻域求和后移位取平均。
// PHASE：0=RGGB、1=GRBG、2=GBRG、3=BGGR；SC2210 使用 BGGR。
// ============================================================================
module bayer_rgb #(
    parameter PHASE = 3
) (
    input             clk,                                                  // 输入：本模块工作时钟
    input             rst_n,                                                // 输入：低有效复位
    input             ce,                                                   // 输入：流水线总时钟使能，低时冻结
    input             s_valid,                                              // 输入：输入数据有效
    input      [71:0] taps,                                                 // 输入：3×3 窗口像素总线
    input      [11:0] x,                                                    // 输入：当前输入像素坐标
    input      [11:0] y,                                                    // 输入：当前输入像素坐标
    output reg        m_valid,                                              // 输出：输出数据有效
    output reg [23:0] rgb                                                   // 输出：RGB888 像素数据
);
    wire [7:0] p[0:8];                                                      // 内部 wire：窗口九点 RAW 像素
    genvar n;

    generate
        for (n = 0; n < 9; n = n + 1) begin : g

            assign p[n] = taps[8*n+:8];
        end
    endgenerate
    wire [9:0] cross_sum = {2'b0, p[1]} + p[3] + p[5] + p[7];               // 内部 wire：上下左右四点之和
    wire [9:0] diag_sum = {2'b0, p[0]} + p[2] + p[6] + p[8];                // 内部 wire：四个对角像素之和
    wire [8:0] horiz = {1'b0, p[3]} + p[5];                                 // 内部 wire：左右像素之和
    wire [8:0] vert = {1'b0, p[1]} + p[7];                                  // 内部 wire：上下像素之和
    wire [1:0] color={y[0],x[0]}^PHASE;                                     // 内部 wire：由坐标奇偶与 Bayer 相位确定中心颜色

    always @(posedge clk or negedge rst_n)
        if (!rst_n) m_valid <= 0;

        else if (ce) begin
            m_valid <= s_valid;
            case (color)
                0: rgb <= {p[4], cross_sum[9:2], diag_sum[9:2]};
                1: rgb <= {horiz[8:1], p[4], vert[8:1]};
                2: rgb <= {vert[8:1], p[4], horiz[8:1]};
                3: rgb <= {diag_sum[9:2], cross_sum[9:2], p[4]};
            endcase
        end
endmodule
