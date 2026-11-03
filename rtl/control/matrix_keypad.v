`timescale 1ns / 1ps

// ============================================================================
// 4×4 矩阵键盘扫描：行输入，列仅拉低或释放；禁止未选列主动输出高电平。
// 96MHz 下每列250us，先释放10us，再选列并等待稳定，四列一轮约1ms。
// 连续16轮相同矩阵确认按下/释放；只接受单键，长按及滑键均不重复触发。
// 检测多键（含无二极管矩阵的鬼键）后锁定，全部释放并消抖后重新使能。
// 位编号 row*4+col；复位后也需先确认全释放，防止上电按住键触发功能。
// ============================================================================
module matrix_keypad #(
    parameter COLUMN_CYCLES = 24000,         // 一列扫描周期，包含释放间隔
    parameter RELEASE_CYCLES = 960,          // 列间全部释放时间，给转换器及上拉恢复
    parameter DEBOUNCE_SCANS = 16            // 相同完整矩阵采样次数，至少2
) (
    input             clk,                  // 输入：96MHz用户时钟
    input             rst_n,                // 输入：低有效复位
    input      [3:0]  key_row,              // 输入：ROW1～ROW4，选中且按下为低
    output     [3:0]  col_oe,               // 输出：列拉低使能，至多一位为1，0表示高阻
    output reg [15:0] pressed,              // 输出：消抖后的单拍单键位图
    output reg [15:0] stable_keys,          // 输出：最近消抖确认的矩阵位图，供调试
    output reg        multi_key,            // 输出：最近一轮检测到多个闭合触点
    output reg        armed                 // 输出：已确认全释放，允许下一次单击
);
    localparam TICK_BITS = $clog2(COLUMN_CYCLES);
    localparam DB_BITS = $clog2(DEBOUNCE_SCANS + 1);
    (* async_reg="true" *) reg [3:0] row_meta;  // 内部：异步行输入第一级同步
    (* async_reg="true" *) reg [3:0] row_sync;  // 内部：异步行输入第二级同步
    reg [TICK_BITS-1:0] phase;              // 内部：列内计时
    reg [1:0] column;                       // 内部：当前扫描列0～3
    reg [15:0] scan_keys;                   // 内部：本轮已采集列的键位
    reg [15:0] candidate;                   // 内部：消抖候选完整矩阵
    reg [DB_BITS-1:0] equal_scans;          // 内部：候选连续相同轮数，饱和计数
    reg [15:0] complete_keys;               // 内部：合入当前列后的完整采样
    integer r;

    assign col_oe = (!rst_n || phase < RELEASE_CYCLES) ? 4'b0000 : (4'b0001 << column);
    wire column_tick = phase == COLUMN_CYCLES - 1;
    wire scan_tick = column_tick && column == 3;
    wire one_key = complete_keys != 0 && (complete_keys & (complete_keys - 16'd1)) == 0;

    always @* begin
        complete_keys = scan_keys;
        for (r = 0; r < 4; r = r + 1)
            complete_keys[r*4 + column] = !row_sync[r];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_meta <= 4'hf;
            row_sync <= 4'hf;
            phase <= 0;
            column <= 0;
            scan_keys <= 0;
            candidate <= 0;
            equal_scans <= 0;
            pressed <= 0;
            stable_keys <= 0;
            multi_key <= 0;
            armed <= 0;
        end
        else begin
            row_meta <= key_row;
            row_sync <= row_meta;
            pressed <= 0;
            if (column_tick) begin
                phase <= 0;
                column <= column + 2'd1;
                scan_keys <= complete_keys;
            end
            else phase <= phase + 1'b1;

            if (scan_tick) begin
                multi_key <= complete_keys != 0 && !one_key;
                // 多键不等消抖就锁定，防止松开部分键后形成一个新的误单击。
                if (complete_keys != 0 && !one_key) armed <= 0;
                if (complete_keys != candidate) begin
                    candidate <= complete_keys;
                    equal_scans <= 1;
                end
                else if (equal_scans < DEBOUNCE_SCANS) begin
                    equal_scans <= equal_scans + 1'b1;
                    if (equal_scans == DEBOUNCE_SCANS - 1) begin
                        stable_keys <= complete_keys;
                        if (complete_keys == 0) armed <= 1;
                        else if (one_key && armed) begin
                            pressed <= complete_keys;
                            armed <= 0;
                        end
                    end
                end
            end
        end
    end
endmodule
