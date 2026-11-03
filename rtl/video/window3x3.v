`timescale 1ns / 1ps

// ============================================================================
// 通用 3×3 窗口：两个历史行缓存加横向移位寄存器，支持整条流水线暂停。
// 同步读 RAM、延迟写回；前两行与前两列不输出，顶层补边保证最终尺寸。
// 窗口按行排列，最低 BITS 位为左上角，最高 BITS 位为右下角。
// ============================================================================
module window3x3 #(
    parameter WIDTH = 1920,
    HEIGHT = 1080,
    BITS = 8
) (
    input                   clk,                                            // 输入：本模块工作时钟
    input                   rst_n,                                          // 输入：低有效复位
    input                   ce,                                             // 输入：流水线总时钟使能，低时冻结
    input                   s_valid,                                        // 输入：输入数据有效
    input      [  BITS-1:0] s_data,                                         // 输入：输入像素数据
    output reg              m_valid,                                        // 输出：输出数据有效
    output reg [9*BITS-1:0] taps,                                           // 输出：3×3 窗口像素总线
    output reg [      11:0] m_x,                                            // 输出：输出像素坐标
    output reg [      11:0] m_y                                             // 输出：输出像素坐标
);
    (* ram_style="block" *) reg [2*BITS-1:0] lines[0:WIDTH-1];              // 内部 reg：两条历史行合并存储的块 RAM
    reg [2*BITS-1:0] q;                                                     // 内部 reg：同步读出的两个历史行像素
    reg [11:0] x = 0;                                                       // 内部 reg：输入光栅列、行计数器
    reg [11:0] y = 0;                                                       // 内部 reg：输入光栅列、行计数器
    reg [11:0] xq;                                                          // 内部 reg：与同步 RAM 数据对齐的坐标
    reg [11:0] yq;                                                          // 内部 reg：与同步 RAM 数据对齐的坐标
    reg vq = 0;                                                             // 内部 reg：同步 RAM 数据有效标志
    reg [BITS-1:0] dq;                                                      // 内部 reg：当前行像素延迟寄存器
    reg [BITS-1:0] a0;                                                      // 内部 reg：上行前两列移位寄存器
    reg [BITS-1:0] a1;                                                      // 内部 reg：上行前两列移位寄存器
    reg [BITS-1:0] b0;                                                      // 内部 reg：中行前两列移位寄存器
    reg [BITS-1:0] b1;                                                      // 内部 reg：中行前两列移位寄存器
    reg [BITS-1:0] c0;                                                      // 内部 reg：下行前两列移位寄存器
    reg [BITS-1:0] c1;                                                      // 内部 reg：下行前两列移位寄存器
    // RAM 同步读、延后一拍写；不依赖同地址同周期读写的器件行为。
    always @(posedge clk)
        if (ce) begin
            if (s_valid) q <= lines[x];
            if (vq) lines[xq] <= {q[BITS-1:0], dq};
        end
    // 有效行列计数和横向移位均受 CE 控制，反压不会破坏窗口对齐。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x       <= 0;
            y       <= 0;
            vq      <= 0;
            m_valid <= 0;
            m_x     <= 0;
            m_y     <= 0;
        end

        else if (ce) begin
            vq      <= s_valid;
            m_valid <= 0;
            if (s_valid) begin
                dq <= s_data;
                xq <= x;
                yq <= y;
                if (x == WIDTH - 1) begin
                    x <= 0;
                    if (y == HEIGHT - 1) y <= 0;
                    else y <= y + 1'b1;
                end
                else x <= x + 1'b1;
            end
            if (vq) begin
                a0 <= a1;
                a1 <= q[2*BITS-1:BITS];
                b0 <= b1;
                b1 <= q[BITS-1:0];
                c0 <= c1;
                c1 <= dq;
                if (xq >= 2 && yq >= 2) begin
                    m_valid <= 1;
                    m_x     <= xq - 2;
                    m_y     <= yq - 2;
                    taps    <= {dq, c1, c0, q[BITS-1:0], b1, b0, q[2*BITS-1:BITS], a1, a0};
                end
            end
        end
    end
endmodule
