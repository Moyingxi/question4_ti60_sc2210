`timescale 1ns / 1ps

// ============================================================================
// 3×3 中值滤波：九级奇偶交换排序得到九点中值，支持等延迟旁路。
// 输出高 8 位保留中心原灰度，低 8 位为滤波结果；旁路仍经过相同寄存器级数。
// ============================================================================
module median9_pipe (
    input         clk,                                                      // 输入：本模块工作时钟
    input         rst_n,                                                    // 输入：低有效复位
    input         ce,                                                       // 输入：流水线总时钟使能，低时冻结
    input         s_valid,                                                  // 输入：输入数据有效
    input  [71:0] taps,                                                     // 输入：3×3 窗口像素总线
    input         enable,                                                   // 输入：功能使能
    output        m_valid,                                                  // 输出：输出数据有效
    output [15:0] gray_filtered                                             // 输出：高字节原灰度，低字节中值或旁路灰度
);
    wire [71:0] stage[0:9];                                                 // 内部 wire：九级排序各级的九点数据
    wire [7:0] center[0:9];                                                 // 内部 wire：原始中心灰度的等延迟旁路链
    wire [9:0] valid;                                                       // 内部 wire：排序各级有效信号链

    assign stage[0]  = taps;
    assign center[0] = taps[39:32];
    assign valid[0]  = s_valid;
    genvar s, k;

    generate
        for (s = 0; s < 9; s = s + 1) begin : sort_stage
            reg  [71:0] data;                                               // 内部 reg：本排序级九点寄存器
            reg  [ 7:0] refgray;                                            // 内部 reg：本排序级原灰度延迟寄存器
            reg         v;                                                  // 内部 reg：本排序级有效寄存器
            wire [71:0] next_data;                                          // 内部 wire：本级相邻点比较交换结果
            for (k = 0; k < 9; k = k + 1) begin : item
                if ((k % 2) == (s % 2) && k < 8) begin

                    assign next_data[k*8+:8]=stage[s][k*8+:8]<stage[s][(k+1)*8+:8]?stage[s][k*8+:8]:stage[s][(k+1)*8+:8];
                end

                else if (k > 0 && ((k - 1) % 2) == (s % 2)) begin

                    assign next_data[k*8+:8]=stage[s][k*8+:8]>stage[s][(k-1)*8+:8]?stage[s][k*8+:8]:stage[s][(k-1)*8+:8];
                end
                else assign next_data[k*8+:8] = stage[s][k*8+:8];
            end

            always @(posedge clk or negedge rst_n)
                if (!rst_n) v <= 0;

                else if (ce) begin
                    data    <= next_data;
                    refgray <= center[s];
                    v       <= valid[s];
                end

            assign stage[s+1]  = data;
            assign center[s+1] = refgray;
            assign valid[s+1]  = v;
        end
    endgenerate

    assign m_valid       = valid[9];
    assign gray_filtered = {center[9], enable ? stage[9][39:32] : center[9]};
endmodule
