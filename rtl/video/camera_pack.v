`timescale 1ns / 1ps

// ============================================================================
// 摄像头打包：每周期四个 RAW8 像素，拼成 128 位数据并附帧内序号及错误位。
// 摄像头不能接受反压；溢出时丢弃余帧，下一帧同步恢复。
// 最后一包延迟到最后一行结束校验，避免发布末行尺寸错误的帧。
// ============================================================================
module camera_pack (
    input              clk,                                                 // 输入：本模块工作时钟
    input              rst_n,                                               // 输入：低有效复位
    input              vs,                                                  // 输入：帧同步信号
    input              de,                                                  // 输入：像素数据有效区
    input      [ 31:0] pixels,                                              // 输入：每周期四个 RAW8 像素，低字节先处理
    output reg [145:0] data,                                                // 输出：数据总线
    output reg         valid,                                               // 输出：数据有效
    input              ready,                                               // 输入：允许接收数据
    output reg [ 31:0] frames,                                              // 输出：帧计数
    output reg [ 31:0] overflow_count,                                      // 输出：采集 FIFO 溢出计数
    output reg [ 31:0] format_errors                                        // 输出：摄像头尺寸异常计数
);
    reg         vsq;                                                        // 内部 reg：上一拍帧同步，用于检测上升沿
    reg         deq;                                                        // 内部 reg：上一拍有效信号，用于检测行结束
    reg         active;                                                     // 内部 reg：正在接收本帧有效区
    reg         drop_frame;                                                 // 内部 reg：当前帧发生溢出，停止继续投递
    reg [  1:0] sub;                                                        // 内部 reg：128 位包内四像素组序号
    reg [127:0] assembled;                                                  // 内部 reg：四组 RAW 像素拼接寄存器
    reg [ 16:0] index;                                                      // 内部 reg：当前帧内数据包序号
    reg [  9:0] line_words;                                                 // 内部 reg：本行四像素组计数，应为 480
    reg [ 10:0] lines;                                                      // 内部 reg：已完成行数计数
    reg         bad;                                                        // 内部 reg：本帧尺寸错误标志
    reg         last_pending;                                               // 内部 reg：最后一包等待末行校验
    reg [127:0] last_packet;                                                // 内部 reg：等待发布的最后一个 128 位包

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vsq            <= 0;
            deq            <= 0;
            active         <= 0;
            drop_frame     <= 1;
            sub            <= 0;
            index          <= 0;
            valid          <= 0;
            frames         <= 0;
            overflow_count <= 0;
            format_errors  <= 0;
            line_words     <= 0;
            lines          <= 0;
            bad            <= 0;
            last_pending   <= 0;
        end
        else begin
            vsq   <= vs;
            deq   <= de;
            valid <= 0;
            if (vs && !vsq) begin
                active       <= 1;
                drop_frame   <= 0;
                sub          <= 0;
                index        <= 0;
                line_words   <= 0;
                lines        <= 0;
                bad          <= 0;
                frames       <= frames + 1'b1;
                last_pending <= 0;
            end
            if (de && active) begin
                line_words            <= line_words + 1'b1;
                assembled[sub*32+:32] <= pixels;
                if (sub == 3) begin
                    data <= {bad, index, pixels, assembled[95:0]};
                    if (index == 129599) begin
                        last_pending <= 1;
                        last_packet  <= {pixels, assembled[95:0]};
                    end

                    else if (index < 129599 && !drop_frame) begin
                        if (ready) valid <= 1;
                        else begin
                            drop_frame     <= 1;
                            overflow_count <= overflow_count + 1'b1;
                        end
                    end
                    index <= index + 1'b1;
                end
                sub <= sub + 1'b1;
            end
            // 行结束后校验尺寸，末包必须等最后一行长度确认后才发布。
            if (deq && !de && active) begin
                line_words <= 0;
                lines      <= lines + 1'b1;
                if (line_words != 480) begin
                    bad           <= 1;
                    format_errors <= format_errors + 1'b1;
                end
                if (lines == 1079) begin
                    active <= 0;
                    if (last_pending && !drop_frame) begin
                        data         <= {bad || (line_words != 480), 17'd129599, last_packet};
                        last_pending <= 0;
                        if (ready) valid <= 1;
                        else begin
                            drop_frame     <= 1;
                            overflow_count <= overflow_count + 1'b1;
                        end
                    end
                end
            end
            if (valid && !ready) begin
                drop_frame     <= 1;
                overflow_count <= overflow_count + 1'b1;
            end
        end
    end
endmodule
