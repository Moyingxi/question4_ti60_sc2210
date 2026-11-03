`timescale 1ns / 1ps

// ============================================================================
// SC2210 上电配置：开漏 I²C 主机，读取寄存器配置 ROM 并逐项写入。
// 96 MHz 输入产生约 100 kHz SCL；检查 ACK、支持时钟拉伸与失败重试。
// ============================================================================
module camera_i2c (
    input             clk,                                                  // 输入：本模块工作时钟
    input             rst_n,                                                // 输入：低有效复位
    input             scl_i,                                                // 输入：I²C 时钟引脚采样
    input             sda_i,                                                // 输入：I²C 数据引脚采样
    output            scl_o,                                                // 输出：开漏输出固定零，由 OE 控制拉低或释放
    output            sda_o,                                                // 输出：开漏输出固定零，由 OE 控制拉低或释放
    output reg        scl_oe,                                               // 输出：开漏拉低使能，高表示驱动低电平
    output reg        sda_oe,                                               // 输出：开漏拉低使能，高表示驱动低电平
    output reg        done,                                                 // 输出：本次处理完成
    output reg [31:0] nack_count,                                           // 输出：累计未应答次数
    output reg [ 8:0] index                                                 // 输出：配置 ROM 当前寄存器索引
);
    reg  [23:0] delay_count;                                                // 内部 reg：上电或寄存器写入等待计数
    reg  [ 7:0] divider;                                                    // 内部 reg：I²C 四相节拍分频计数
    reg  [ 3:0] state;                                                      // 内部 reg：I²C 起始、发送、应答、停止状态
    reg  [ 1:0] phase;                                                      // 内部 reg：每个 I²C 位的四相时序
    reg  [ 1:0] byte_number;                                                // 内部 reg：当前发送字节序号 0～3
    reg  [ 2:0] bit_number;                                                 // 内部 reg：当前发送位序号
    reg  [ 2:0] retries;                                                    // 内部 reg：当前配置失败重试次数
    reg  [31:0] tx;                                                         // 内部 reg：从机地址、寄存器地址及数据移位寄存器
    reg         failed;                                                     // 内部 reg：当前事务出现 NACK
    (* async_reg="true" *) reg  [ 1:0] scl_sync;                            // 内部 reg：I²C 引脚两级同步采样
    (* async_reg="true" *) reg  [ 1:0] sda_sync;                            // 内部 reg：I²C 引脚两级同步采样
    wire [23:0] lut;                                                        // 内部 wire：ROM 输出的 16 位地址及 8 位数据
    wire [ 8:0] size;                                                       // 内部 wire：配置表有效项数

    I2C_SC2210_19201080_4Lanes_Config rom (
        index,
        lut,
        size
    );

    assign scl_o = 0;
    assign sda_o = 0;
    wire tick = divider == 239;                                             // 内部 wire：四相状态机推进节拍

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_sync    <= 3;
            sda_sync    <= 3;
            scl_oe      <= 0;
            sda_oe      <= 0;
            done        <= 0;
            nack_count  <= 0;
            index       <= 0;
            delay_count <= 1920000;
            divider     <= 0;
            state       <= 0;
            phase       <= 0;
            retries     <= 0;
            byte_number <= 0;
            bit_number  <= 7;
            tx          <= 0;
            failed      <= 0;
        end
        else begin
            scl_sync <= {scl_sync[0], scl_i};
            sda_sync <= {sda_sync[0], sda_i};
            if (tick) divider <= 0;
            else divider <= divider + 1'b1;
            if (delay_count != 0) delay_count <= delay_count - 1'b1;

            else if (tick && !done)
                case (state)
                    0: begin
                        scl_oe <= 0;
                        sda_oe <= 0;
                        tx     <= {8'h60, lut};
                        phase  <= 0;
                        failed <= 0;
                        if (scl_sync[1] && sda_sync[1]) state <= 1;
                    end
                    1: begin
                        sda_oe <= 1;
                        state  <= 2;
                    end
                    2: begin
                        scl_oe      <= 1;
                        bit_number  <= 7;
                        byte_number <= 0;
                        phase       <= 0;
                        state       <= 3;
                    end
                    3:
                    case (phase)
                        0: begin
                            scl_oe <= 1;
                            sda_oe <= !tx[31];
                            phase  <= 1;
                        end
                        1: begin
                            scl_oe <= 0;
                            phase  <= 2;
                        end
                        2: if (scl_sync[1]) phase <= 3;
                        3: begin
                            scl_oe <= 1;
                            tx     <= {tx[30:0], 1'b0};
                            phase  <= 0;
                            if (bit_number == 0) state <= 4;
                            else bit_number <= bit_number - 1'b1;
                        end
                    endcase
                    4:
                    case (phase)
                        0: begin
                            sda_oe <= 0;
                            phase  <= 1;
                        end
                        1: begin
                            scl_oe <= 0;
                            phase  <= 2;
                        end
                        2:
                        if (scl_sync[1]) begin
                            if (sda_sync[1]) begin
                                failed     <= 1;
                                nack_count <= nack_count + 1'b1;
                            end
                            phase <= 3;
                        end
                        3: begin
                            scl_oe     <= 1;
                            phase      <= 0;
                            bit_number <= 7;
                            if (byte_number == 3 || failed) state <= 5;
                            else begin
                                byte_number <= byte_number + 1'b1;
                                state       <= 3;
                            end
                        end
                    endcase
                    5: begin
                        scl_oe <= 1;
                        sda_oe <= 1;
                        state  <= 6;
                    end
                    6: begin
                        scl_oe <= 0;
                        state  <= 7;
                    end
                    7:
                    if (scl_sync[1]) begin
                        sda_oe <= 0;
                        state  <= 8;
                    end
                    8: begin
                        state <= 0;
                        if (failed) begin
                            retries     <= retries + 1'b1;
                            delay_count <= 960000;
                            if (retries == 7) begin
                                index       <= 0;
                                retries     <= 0;
                                delay_count <= 9600000;
                            end
                        end
                        else begin
                            retries <= 0;
                            if (index == size - 1) done <= 1;
                            else index <= index + 1'b1;
                            delay_count <= index == 0 ? 960000 : 9600;
                        end
                    end
                    default: state <= 0;
                endcase
        end
    end
endmodule
