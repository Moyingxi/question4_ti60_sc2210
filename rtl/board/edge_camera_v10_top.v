`timescale 1ns / 1ps

// ============================================================================
// 第三版系统顶层：连接 CSI 接收、DDR3 帧缓存、图像算法、HDMI 和 Debugger。
// clk_sys=96 MHz，clk_pixel_2x=148.5 MHz；各数据通路通过异步 FIFO 跨域。
// DDR、CSI、LVDS 和 JTAG 端口对应 Interface Designer 生成的接口。
// ============================================================================
module edge_camera_v10_top (
    input clk_24m,                                                          // 输入：板载 24 MHz 参考时钟
    output sys_pll_rstn_o,                                                  // 输出：系统 PLL 低有效复位输出
    input clk_sys,                                                          // 输入：96 MHz 系统与 DDR 用户接口时钟
    input clk_pixel_2x,                                                     // 输入：148.5 MHz 算法及 HDMI 像素时钟，名称沿用接口
    input sys_pll_lock,                                                     // 输入：系统 PLL 锁定指示
    output ddr_pll_rstn_o,                                                  // 输出：DDR PLL 低有效复位输出
    input tdqss_clk,                                                        // 输入：DDR PHY DQS 相位时钟
    input core_clk,                                                         // 输入：192 MHz DDR 内核时钟
    input tac_clk,                                                          // 输入：DDR PHY 地址命令时钟
    input twd_clk,                                                          // 输入：DDR PHY 写数据时钟
    input ddr_pll_lock,                                                     // 输入：DDR PLL 锁定指示
    output [2:0] shift,                                                     // 输出：DDR 校准相移控制
    output [4:0] shift_sel,                                                 // 输出：DDR 相移时钟选择
    output shift_ena,                                                       // 输出：DDR 相移更新使能
    output [14:0] addr,                                                     // 输出：DDR3 实际使用的 15 位地址
    output [2:0] ba,                                                        // 输出：DDR3 Bank 地址
    output we,                                                              // 输出：DDR3 写命令控制
    output reset,                                                           // 输出：DDR3 芯片复位输出
    output ras,                                                             // 输出：DDR3 行地址选通控制
    output cas,                                                             // 输出：DDR3 列地址选通控制
    output odt,                                                             // 输出：DDR3 片上终端控制
    output cke,                                                             // 输出：DDR3 时钟使能
    output cs,                                                              // 输出：DDR3 片选
    input [15:0] i_dq_hi,                                                   // 输入：DDR DQ 上半拍输入
    input [15:0] i_dq_lo,                                                   // 输入：DDR DQ 下半拍输入
    output [15:0] o_dq_hi,                                                  // 输出：DDR DQ 上半拍输出
    output [15:0] o_dq_lo,                                                  // 输出：DDR DQ 下半拍输出
    output [15:0] o_dq_oe,                                                  // 输出：DDR 数据输出使能
    output [1:0] o_dm_hi,                                                   // 输出：DDR 上半拍字节掩码
    output [1:0] o_dm_lo,                                                   // 输出：DDR 下半拍字节掩码
    input [1:0] i_dqs_hi,                                                   // 输入：DDR DQS 上半拍输入
    input [1:0] i_dqs_lo,                                                   // 输入：DDR DQS 下半拍输入
    output [1:0] o_dqs_hi,                                                  // 输出：DDR DQS 上半拍输出
    output [1:0] o_dqs_lo,                                                  // 输出：DDR DQS 下半拍输出
    output [1:0] o_dqs_oe,                                                  // 输出：DDR DQS 正端输出使能
    output [1:0] o_dqs_n_oe,                                                // 输出：DDR DQS 负端输出使能
    output clk_p_hi,                                                        // 输出：DDR 正时钟上半拍电平
    output clk_p_lo,                                                        // 输出：DDR 正时钟下半拍电平
    output clk_n_hi,                                                        // 输出：DDR 负时钟上半拍电平
    output clk_n_lo,                                                        // 输出：DDR 负时钟下半拍电平
    output csi_ctl0_o,                                                      // 输出：摄像头扩展控制 GPIO 输出电平
    output csi_ctl0_oe,                                                     // 输出：摄像头扩展控制 GPIO 输出使能
    input csi_ctl0_i,                                                       // 输入：摄像头扩展控制 GPIO 输入采样（本版未使用）
    output csi_ctl1_o,                                                      // 输出：摄像头扩展控制 GPIO 输出电平
    output csi_ctl1_oe,                                                     // 输出：摄像头扩展控制 GPIO 输出使能
    input csi_ctl1_i,                                                       // 输入：摄像头扩展控制 GPIO 输入采样（本版未使用）
    output csi_scl_o,                                                       // 输出：摄像头 I²C 输出固定零
    output csi_scl_oe,                                                      // 输出：摄像头 I²C 开漏拉低使能
    input csi_scl_i,                                                        // 输入：摄像头 I²C 引脚采样
    output csi_sda_o,                                                       // 输出：摄像头 I²C 输出固定零
    output csi_sda_oe,                                                      // 输出：摄像头 I²C 开漏拉低使能
    input csi_sda_i,                                                        // 输入：摄像头 I²C 引脚采样
    input csi_rxc_lp_p_i,                                                   // 输入：CSI rxc 低功耗正端采样
    input csi_rxc_lp_n_i,                                                   // 输入：CSI rxc 低功耗负端采样
    output csi_rxc_hs_en_o,                                                 // 输出：CSI rxc 高速接收使能
    output csi_rxc_hs_term_en_o,                                            // 输出：CSI rxc 高速终端使能
    input csi_rxc_i,                                                        // 输入：CSI 接收高速字节时钟
    output csi_rxd0_rst_o,                                                  // 输出：CSI rxd0 接收器复位
    output csi_rxd0_hs_en_o,                                                // 输出：CSI rxd0 高速接收使能
    output csi_rxd0_hs_term_en_o,                                           // 输出：CSI rxd0 高速终端使能
    input csi_rxd0_lp_p_i,                                                  // 输入：CSI rxd0 低功耗正端采样
    input csi_rxd0_lp_n_i,                                                  // 输入：CSI rxd0 低功耗负端采样
    input [7:0] csi_rxd0_hs_i,                                              // 输入：CSI rxd0 高速解串数据
    output csi_rxd1_rst_o,                                                  // 输出：CSI rxd1 接收器复位
    output csi_rxd1_hs_en_o,                                                // 输出：CSI rxd1 高速接收使能
    output csi_rxd1_hs_term_en_o,                                           // 输出：CSI rxd1 高速终端使能
    input csi_rxd1_lp_n_i,                                                  // 输入：CSI rxd1 低功耗负端采样
    input csi_rxd1_lp_p_i,                                                  // 输入：CSI rxd1 低功耗正端采样
    input [7:0] csi_rxd1_hs_i,                                              // 输入：CSI rxd1 高速解串数据
    output csi_rxd2_rst_o,                                                  // 输出：CSI rxd2 接收器复位
    output csi_rxd2_hs_en_o,                                                // 输出：CSI rxd2 高速接收使能
    output csi_rxd2_hs_term_en_o,                                           // 输出：CSI rxd2 高速终端使能
    input csi_rxd2_lp_p_i,                                                  // 输入：CSI rxd2 低功耗正端采样
    input csi_rxd2_lp_n_i,                                                  // 输入：CSI rxd2 低功耗负端采样
    input [7:0] csi_rxd2_hs_i,                                              // 输入：CSI rxd2 高速解串数据
    output csi_rxd3_rst_o,                                                  // 输出：CSI rxd3 接收器复位
    output csi_rxd3_hs_en_o,                                                // 输出：CSI rxd3 高速接收使能
    output csi_rxd3_hs_term_en_o,                                           // 输出：CSI rxd3 高速终端使能
    input csi_rxd3_lp_p_i,                                                  // 输入：CSI rxd3 低功耗正端采样
    input csi_rxd3_lp_n_i,                                                  // 输入：CSI rxd3 低功耗负端采样
    input [7:0] csi_rxd3_hs_i,                                              // 输入：CSI rxd3 高速解串数据
    output hdmi_txc_oe,                                                     // 输出：HDMI txc 串行器输出使能
    output hdmi_txd0_oe,                                                    // 输出：HDMI txd0 串行器输出使能
    output hdmi_txd1_oe,                                                    // 输出：HDMI txd1 串行器输出使能
    output hdmi_txd2_oe,                                                    // 输出：HDMI txd2 串行器输出使能
    output hdmi_txc_rst_o,                                                  // 输出：HDMI txc 串行器复位
    output hdmi_txd0_rst_o,                                                 // 输出：HDMI txd0 串行器复位
    output hdmi_txd1_rst_o,                                                 // 输出：HDMI txd1 串行器复位
    output hdmi_txd2_rst_o,                                                 // 输出：HDMI txd2 串行器复位
    output [9:0] hdmi_txc_o,                                                // 输出：HDMI txc 10 位 TMDS 并行码字
    output [9:0] hdmi_txd0_o,                                               // 输出：HDMI txd0 10 位 TMDS 并行码字
    output [9:0] hdmi_txd1_o,                                               // 输出：HDMI txd1 10 位 TMDS 并行码字
    output [9:0] hdmi_txd2_o,                                               // 输出：HDMI txd2 10 位 TMDS 并行码字
    input video_pll_lock,                                                   // 输入：视频 PLL 锁定指示
    input clk_video_ref,                                                    // 输入：99 MHz 视频 PLL 参考时钟
    input clk_video_fb,                                                     // 输入：198 MHz 视频 PLL 反馈时钟
    input clk_pixel_10x,                                                    // 输入：742.5 MHz TMDS 串行时钟
    output [7:0] seg_o, // ATK A..G,DOT, active high through P4 level shifters
    output [3:0] seg_sel_o, // ATK CH1..CH4, active high
    output [5:0] led_o,                                                     // 输出：板载六个 LED 状态输出
    output video_pll_rstn_o,                                                // 输出：视频 PLL 低有效复位输出
    input key_plus_i,                                                       // 输入：板载阈值增加按键，低有效
    input key_minus_i,                                                      // 输入：板载阈值减小按键，低有效
    input  [3:0] key_row,                                                   // 输入：矩阵ROW1～ROW4，外部上拉，按下拉低
    input  [3:0] key_col_in,                                                // 输入：矩阵列引脚回读，仅供调试
    output [3:0] key_col,                                                   // 输出：列驱动数据固定为0，通过独立OE实现高阻
    output [3:0] key_col_oe,                                                // 输出：列拉低使能，未选列释放
    input jtag_inst1_CAPTURE,                                               // 输入：Debugger 用户 JTAG CAPTURE 信号
    input jtag_inst1_DRCK,                                                  // 输入：Debugger 用户 JTAG DRCK 信号
    input jtag_inst1_RESET,                                                 // 输入：Debugger 用户 JTAG RESET 信号
    input jtag_inst1_RUNTEST,                                               // 输入：Debugger 用户 JTAG RUNTEST 信号
    input jtag_inst1_SEL,                                                   // 输入：Debugger 用户 JTAG SEL 信号
    input jtag_inst1_SHIFT,                                                 // 输入：Debugger 用户 JTAG SHIFT 信号
    input jtag_inst1_TCK,                                                   // 输入：Debugger 用户 JTAG TCK 信号
    input jtag_inst1_TDI,                                                   // 输入：Debugger 用户 JTAG TDI 信号
    input jtag_inst1_TMS,                                                   // 输入：Debugger 用户 JTAG TMS 信号
    input jtag_inst1_UPDATE,                                                // 输入：Debugger 用户 JTAG UPDATE 信号
    output jtag_inst1_TDO                                                   // 输出：Debugger 用户 JTAG TDO 信号
);
    wire         cal_done;                                                  // 内部 wire：DDR 校准完成
    wire         cal_pass;                                                  // 内部 wire：DDR 校准通过
    wire [  2:0] cal_shift_val;                                             // 内部 wire：DDR 校准选定相移
    wire [  7:0] axi_aid;                                                   // 内部 wire：AXI 地址事务 ID
    wire [ 31:0] axi_aaddr;                                                 // 内部 wire：AXI 字节地址
    wire [  7:0] axi_alen;                                                  // 内部 wire：AXI 突发拍数减一
    wire [  2:0] axi_asize;                                                 // 内部 wire：AXI 每拍字节数指数，4 表示 16 字节
    wire [  1:0] axi_aburst;                                                // 内部 wire：AXI 突发类型，INCR 递增
    wire [  1:0] axi_alock;                                                 // 内部 wire：AXI 地址锁控制，未使用
    wire         axi_avalid;                                                // 内部 wire：AXI 地址有效
    wire         axi_aready;                                                // 内部 wire：AXI 地址接收就绪
    wire         axi_atype;                                                 // 内部 wire：共用地址通道方向：1 写，0 读
    wire [  7:0] axi_wid;                                                   // 内部 wire：AXI 写事务 ID
    wire [127:0] axi_wdata;                                                 // 内部 wire：AXI 128 位写数据
    wire [ 15:0] axi_wstrb;                                                 // 内部 wire：AXI 16 字节写使能
    wire         axi_wlast;                                                 // 内部 wire：AXI 写突发最后一拍
    wire         axi_wvalid;                                                // 内部 wire：AXI 写数据有效
    wire         axi_wready;                                                // 内部 wire：AXI 写数据就绪
    wire [  7:0] axi_rid;                                                   // 内部 wire：AXI 读返回 ID
    wire [127:0] axi_rdata;                                                 // 内部 wire：AXI 128 位读数据
    wire         axi_rlast;                                                 // 内部 wire：AXI 读突发最后一拍
    wire         axi_rvalid;                                                // 内部 wire：AXI 读数据有效
    wire         axi_rready;                                                // 内部 wire：AXI 读数据接收就绪
    wire [  1:0] axi_rresp;                                                 // 内部 wire：AXI 读响应，零为成功
    wire [  7:0] axi_bid;                                                   // 内部 wire：AXI 写响应 ID
    wire [  1:0] axi_bresp;                                                 // 内部 wire：AXI 写响应，零为成功
    wire         axi_bvalid;                                                // 内部 wire：AXI 写响应有效
    wire         axi_bready;                                                // 内部 wire：AXI 写响应接收就绪
    wire [  7:0] cal_fail_log;                                              // 内部 wire：DDR 校准失败记录
    wire [ 15:0] ddr_addr;                                                  // 内部 wire：DDR IP 16 位地址，外接仅使用低 15 位
    wire         rst_ui_n;                                                  // 内部 wire：96 MHz 用户接口域同步释放复位
    wire         rst_pixel_n;                                               // 内部 wire：148.5 MHz 像素域同步释放复位
    wire         rst_rx_n;                                                  // 内部 wire：CSI 接收域同步释放复位

    assign sys_pll_rstn_o   = 1'b1;
    assign ddr_pll_rstn_o   = sys_pll_lock;
    assign video_pll_rstn_o = sys_pll_lock;
    // PLL 全部锁定后分别在用户域与像素域同步释放复位。
    reset_sync ui_reset (
        clk_sys,
        sys_pll_lock && ddr_pll_lock && video_pll_lock,
        rst_ui_n
    );

    reset_sync pixel_reset (
        clk_pixel_2x,
        sys_pll_lock && ddr_pll_lock && video_pll_lock,
        rst_pixel_n
    );
    wire        rx_clk;                                                     // 内部 wire：CSI 解码输出字节时钟
    wire [ 3:0] rx_vs;                                                      // 内部 wire：CSI 虚拟通道帧同步
    wire [ 3:0] rx_hs;                                                      // 内部 wire：CSI 虚拟通道行有效
    wire        rx_de;                                                      // 内部 wire：CSI 解码数据有效，须与行有效联合使用
    wire [47:0] rx_raw;                                                     // 内部 wire：CSI 接收器四像素解码总线

    reset_sync rx_reset (
        rx_clk,
        rst_ui_n,
        rst_rx_n
    );
    function [7:0] lane_bits(input [7:0] a);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1) lane_bits[i] = !a[7-i];
        end
    endfunction

    wire [47:0] rx_diag;
    wire [31:0] rx_lane_bytes;
    assign rx_lane_bytes={lane_bits(csi_rxd3_hs_i),lane_bits(csi_rxd2_hs_i),
                          lane_bits(csi_rxd1_hs_i),lane_bits(csi_rxd0_hs_i)};
    wire rx_lp_p,rx_lp_n;
    v8_csi_lp_align csi_lp_align (
        .clk(csi_rxc_i),.rst(!rst_ui_n),
        .lp_p(csi_rxd0_lp_n_i),.lp_n(csi_rxd0_lp_p_i),
        .rx_lp_p(rx_lp_p),.rx_lp_n(rx_lp_n)
    );
    // Preserve physical enables; only the decoder's LP gate is pipelined.
    assign csi_rxd0_hs_en_o = !(csi_rxd0_lp_n_i | csi_rxd0_lp_p_i);
    assign csi_rxd0_hs_term_en_o = csi_rxd0_hs_en_o;
    MIPIRx4LaneFre mipi_rx (
        .sclk_i               (clk_sys),
        .srst_i               (!rst_ui_n),
        .mipi_rx_byteclk_i    (csi_rxc_i),
        .mipi_rx_d0_i         (rx_lane_bytes[7:0]),
        .mipi_rx_d1_i         (rx_lane_bytes[15:8]),
        .mipi_rx_d2_i         (rx_lane_bytes[23:16]),
        .mipi_rx_d3_i         (rx_lane_bytes[31:24]),
        .mipi_rx_clk_lp_p_i   (csi_rxc_lp_p_i),
        .mipi_rx_clk_lp_n_i   (csi_rxc_lp_n_i),
        .mipi_rx_d0_lp_p_i    (rx_lp_p),
        .mipi_rx_d0_lp_n_i    (rx_lp_n),
        .mipi_rx_rst_o        (),
        .mipi_rx_rst_n_o      (),
        .mipi_rx_clk_hs_en_o  (csi_rxc_hs_en_o),
        .mipi_rx_dat_hs_en_o  (),
        .mipi_rx_clk_term_en_o(csi_rxc_hs_term_en_o),
        .mipi_rx_dat_term_en_o(),
        .CLK                  (rx_clk),
        .VSYNC                (rx_vs),
        .HSYNC                (rx_hs),
        .DE                   (rx_de),
        .DAT                  (rx_raw),
        .INDEX                (),
        .RX_DIAG              (rx_diag)
    );

    assign {csi_rxd3_hs_en_o, csi_rxd2_hs_en_o, csi_rxd1_hs_en_o} = {3{csi_rxd0_hs_en_o}};
    assign {csi_rxd3_hs_term_en_o, csi_rxd2_hs_term_en_o, csi_rxd1_hs_term_en_o} = {3{csi_rxd0_hs_term_en_o}};
    assign {csi_rxd0_rst_o, csi_rxd1_rst_o, csi_rxd2_rst_o, csi_rxd3_rst_o} = {4{!rst_ui_n}};
    assign csi_ctl0_o = 0;
    assign csi_ctl1_o = 0;
    assign csi_ctl0_oe = 0;
    assign csi_ctl1_oe = 0;
    wire        i2c_done;                                                   // 内部 wire：SC2210 配置完成
    wire [31:0] i2c_nacks;                                                  // 内部 wire：SC2210 I²C 未应答累计次数
    wire [ 8:0] i2c_index;                                                  // 内部 wire：SC2210 当前配置项序号

    camera_i2c i2c (
        clk_sys,
        rst_ui_n,
        csi_scl_i,
        csi_sda_i,
        csi_scl_o,
        csi_sda_o,
        csi_scl_oe,
        csi_sda_oe,
        i2c_done,
        i2c_nacks,
        i2c_index
    );
    wire freeze_press;                                                     // 内部：冻结键单次按下脉冲
    wire replay_press;                                                     // 内部：回放键单次按下脉冲
    wire [1:0] playback_mode;                                              // 内部：实时/冻结/回放/暂停
    wire [8:0] history_count;                                              // 内部：有效历史帧数
    wire [8:0] replay_remaining;                                           // 内部：剩余待播放帧数
    wire history_busy;                                                     // 内部：历史写入尚未完成
    wire replay_waiting;                                                   // 内部：回放等待在途录制收尾
    wire matrix_plus_press;                                                // 内部：R2C2阈值增加
    wire matrix_minus_press;                                               // 内部：R2C1阈值减少
    wire matrix_median_press;                                              // 内部：R1C3中值启用/旁路
    wire [15:0] matrix_pressed;                                            // 内部：消抖后单拍键位
    // JTAG自检只注入同一套按键脉冲；默认0，不改变矩阵按键分配。
    wire [15:0] debug_keys;
    reg [15:0] debug_keys_q;
    wire [15:0] control_pressed=matrix_pressed | (debug_keys & ~debug_keys_q);
    always @(posedge clk_sys or negedge rst_ui_n)
        if(!rst_ui_n) debug_keys_q<=0;
        else debug_keys_q<=debug_keys;
    wire [15:0] matrix_stable;                                             // 内部：稳定键位，供Debugger查看
    wire matrix_multi;                                                     // 内部：最近扫描检测到多键
    wire matrix_armed;                                                     // 内部：已释放，允许下一次单击
    assign key_col = 4'b0000;
    matrix_controls keypad (
        .clk(clk_sys), .rst_n(rst_ui_n), .key_row(key_row), .col_oe(key_col_oe),
        .freeze_press(freeze_press), .replay_press(replay_press),
        .median_press(matrix_median_press), .minus_press(matrix_minus_press),
        .plus_press(matrix_plus_press), .pressed(matrix_pressed),
        .stable_keys(matrix_stable), .multi_key(matrix_multi), .armed(matrix_armed)
    );
    wire [10:0] threshold;                                                  // 内部 wire：边缘判决阈值
    wire        median;                                                     // 内部 wire：中值滤波启用状态
    wire [10:0] threshold_low;
    wire canny_enable,color_enable,overlay_enable,select_low;
    wire [1:0] compare_view;
    wire [2:0] shape_control;
    wire [31:0] controls_telemetry;
    wire compare_edge=compare_view==2;
    wire compare_active,selected_b;
    wire [8:0] compare_index_a,compare_index_b;
    wire [31:0] canny_passes;
    v8_controls #(
        .DEBOUNCE_CYCLES(1440000)
    ) keys (
        clk_sys,
        rst_ui_n,
        key_plus_i,
        key_minus_i,
        control_pressed,
        threshold,threshold_low,
        median,canny_enable,color_enable,overlay_enable,compare_view,select_low,shape_control,controls_telemetry
    );
    wire [31:0] camera_frames;                                              // 内部 wire：接收端帧同步计数
    wire [31:0] camera_overflow;                                            // 内部 wire：摄像头 FIFO 溢出计数
    wire [31:0] camera_format_errors;                                       // 内部 wire：摄像头帧尺寸错误计数
    wire rx_pixel_valid=rx_de&&rx_hs[0];                                    // 内部 wire：RAW 有效像素组，rx_de 与 rx_hs[0] 同时有效
    wire capture_enabled_n;                                                 // 内部 wire：DDR 与摄像头就绪后同步释放的采集复位

    reset_sync capture_start (
        rx_clk,
        rst_ui_n && cal_done && cal_pass && i2c_done,
        capture_enabled_n
    );
    reg [11:0] observed_line_words = 0;                                     // 内部 reg：当前行四像素组计数
    reg [11:0] camera_line_words = 0;                                       // 内部 reg：最近完整行的四像素组数，应为 480
    reg [21:0] observed_frame_words = 0;                                    // 内部 reg：当前帧四像素组计数
    reg [21:0] camera_frame_words = 0;                                      // 内部 reg：最近完整帧四像素组数，应为 518400
    reg        observed_de = 0;                                             // 内部 reg：有效像素组延迟，用于行结束检测
    reg        observed_vs = 0;                                             // 内部 reg：帧同步延迟，用于帧边沿检测

    always @(posedge rx_clk) begin
        observed_de <= rx_pixel_valid;
        observed_vs <= rx_vs[0];
        if (rx_pixel_valid) begin
            observed_line_words  <= observed_line_words + 1'b1;
            observed_frame_words <= observed_frame_words + 1'b1;
        end
        if (observed_de && !rx_pixel_valid) begin
            camera_line_words   <= observed_line_words;
            observed_line_words <= 0;
        end
        if (rx_vs[0] && !observed_vs) begin
            camera_frame_words   <= observed_frame_words;
            observed_frame_words <= 0;
        end
    end
    wire [145:0] cap_in;                                                    // 内部 wire：采集 FIFO 写端数据
    wire [145:0] cap_data;                                                  // 内部 wire：带序号及错误位的采集包
    wire         cap_in_valid;                                              // 内部 wire：采集 FIFO 写端有效标志
    wire         cap_in_ready;                                              // 内部 wire：采集 FIFO 写端接收就绪
    wire         cap_valid;                                                 // 内部 wire：采集包有效
    wire         cap_ready;                                                 // 内部 wire：采集包接收就绪
    wire [ 11:0] cap_level;                                                 // 内部 wire：采集 FIFO 当前水位

    wire [31:0] ordered_raw_pixels;
    sc2210_raw8_unpack raw_order(rx_raw,ordered_raw_pixels);
    camera_pack packer (
        rx_clk,
        capture_enabled_n,
        rx_vs[0],
        rx_pixel_valid,
        ordered_raw_pixels,
        cap_in,
        cap_in_valid,
        cap_in_ready,
        camera_frames,
        camera_overflow,
        camera_format_errors
    );

    async_fifo #(146, 11) capture_fifo (
        rx_clk,
        rst_rx_n,
        cap_in,
        cap_in_valid,
        cap_in_ready
        ,,
        clk_sys,
        rst_ui_n,
        cap_data,
        cap_valid,
        cap_ready,
        cap_level
    );
    wire [127:0] raw_in;                                                    // 内部 wire：RAW FIFO 写端数据
    wire [127:0] raw_out;                                                   // 内部 wire：RAW FIFO 读端数据
    wire [127:0] result_in;                                                 // 内部 wire：结果 FIFO 写端数据
    wire [127:0] result_data;                                               // 内部 wire：128 位结果数据
    wire         raw_in_valid;                                              // 内部 wire：RAW FIFO 写端有效标志
    wire         raw_in_ready;                                              // 内部 wire：RAW FIFO 写端接收就绪
    wire         raw_out_valid;                                             // 内部 wire：RAW FIFO 读端有效标志
    wire         raw_out_ready;                                             // 内部 wire：RAW FIFO 读端接收就绪
    wire         result_in_valid;                                           // 内部 wire：结果 FIFO 写端有效标志
    wire         result_in_ready;                                           // 内部 wire：结果 FIFO 写端接收就绪
    wire         result_valid;                                              // 内部 wire：结果数据有效
    wire         result_ready;                                              // 内部 wire：结果接收就绪
    wire [ 10:0] raw_level;                                                 // 内部 wire：RAW FIFO 当前水位
    wire [ 10:0] result_level;                                              // 内部 wire：结果 FIFO 当前水位

    async_fifo #(128, 10) raw_fifo (
        clk_sys,
        rst_ui_n,
        raw_in,
        raw_in_valid,
        raw_in_ready,
        raw_level,
        clk_pixel_2x,
        rst_pixel_n,
        raw_out,
        raw_out_valid,
        raw_out_ready,
    );

    async_fifo #(128, 10) result_fifo (
        clk_pixel_2x,
        rst_pixel_n,
        result_in,
        result_in_valid,
        result_in_ready
        ,,
        clk_sys,
        rst_ui_n,
        result_data,
        result_valid,
        result_ready,
        result_level
    );
    wire [25:0] cmd_in;
    wire [25:0] cmd_out;
    wire        cmd_in_valid;                                               // 内部 wire：帧命令 FIFO 写端有效标志
    wire        cmd_in_ready;                                               // 内部 wire：帧命令 FIFO 写端接收就绪
    wire        cmd_out_valid;                                              // 内部 wire：帧命令 FIFO 读端有效标志
    wire        cmd_out_ready;                                              // 内部 wire：帧命令 FIFO 读端接收就绪

    async_fifo #(26, 2) command_fifo (
        clk_sys,
        rst_ui_n,
        cmd_in,
        cmd_in_valid,
        cmd_in_ready
        ,,
        clk_pixel_2x,
        rst_pixel_n,
        cmd_out,
        cmd_out_valid,
        cmd_out_ready,
    );
    wire processor_busy;                                                    // 内部 wire：算法整帧处理忙
    wire processor_done;                                                    // 内部 wire：算法整帧完成脉冲

    wire [36:0] wb_config,wb_applied;
    wire wb_ack;wire [319:0] wb_snapshot;
    wire diag_request,diag_ack;
    wire [319:0] diag_snapshot;
    wire [1:0] diag_mode,diag_active_mode;
    v8_processor_io proc (
        clk_pixel_2x,
        rst_pixel_n,
        cmd_out,
        cmd_out_valid,
        cmd_out_ready,
        raw_out,
        raw_out_valid,
        raw_out_ready,
        result_in,
        result_in_valid,
        result_in_ready,
        processor_done,
        processor_busy,diag_request,diag_ack,diag_snapshot,wb_config,wb_applied,wb_ack,wb_snapshot
    );
    wire [9:0] line_in;                                                     // 内部 wire：显示行请求 FIFO 写端数据
    wire [9:0] line_request;                                                // 内部 wire：待预取的缩小图像行号
    wire       line_in_valid;                                               // 内部 wire：显示行请求 FIFO 写端有效标志
    wire       line_in_ready;                                               // 内部 wire：显示行请求 FIFO 写端接收就绪
    wire       line_valid;                                                  // 内部 wire：行请求有效
    wire       line_ready;                                                  // 内部 wire：行请求接收就绪

    async_fifo #(10, 4) line_fifo (
        clk_pixel_2x,
        rst_pixel_n,
        line_in,
        line_in_valid,
        line_in_ready
        ,,
        clk_sys,
        rst_ui_n,
        line_request,
        line_valid,
        line_ready,
    );
    wire [151:0] display_in;
    wire [151:0] display_out;
    wire         display_in_valid;                                          // 内部 wire：显示数据 FIFO 写端有效标志
    wire         display_in_ready;                                          // 内部 wire：显示数据 FIFO 写端接收就绪
    wire         display_out_valid;                                         // 内部 wire：显示数据 FIFO 读端有效标志
    wire         display_out_ready;                                         // 内部 wire：显示数据 FIFO 读端接收就绪
    wire [  9:0] display_level;                                             // 内部 wire：显示 FIFO 当前水位
    reg [31:0] display_sample;
    wire [17:0] sample_address;
    reg [127:0] sample_a,sample_b;
    reg [23:0] sample_header_a,sample_header_b;
    reg [31:0] sample_seq_a,sample_seq_b;
    always @(posedge clk_sys or negedge rst_ui_n) begin
        if(!rst_ui_n) begin
            sample_a<=0;sample_b<=0;sample_header_a<=0;sample_header_b<=0;
            sample_seq_a<=0;sample_seq_b<=0;
        end else if(display_in_valid && display_in_ready && display_in[145:128]==sample_address) begin
            if(display_in[151]) begin
                sample_b<=display_in[127:0];sample_header_b<=display_in[151:128];sample_seq_b<=sample_seq_b+1'b1;
            end else begin
                sample_a<=display_in[127:0];sample_header_a<=display_in[151:128];sample_seq_a<=sample_seq_a+1'b1;
            end
        end
    end
    always @(posedge clk_sys or negedge rst_ui_n)
        if(!rst_ui_n) display_sample<=0;
        else if(display_in_valid && display_in_ready &&
                display_in[145:136]==270 && display_in[135:128]==120 && !display_in[148])
            display_sample<=display_in[31:0];

    async_fifo #(152, 9) display_fifo (
        clk_sys,
        rst_ui_n,
        display_in,
        display_in_valid,
        display_in_ready,
        display_level,
        clk_pixel_2x,
        rst_pixel_n,
        display_out,
        display_out_valid,
        display_out_ready,
    );
    wire [23:0] rgb;                                                        // 内部 wire：RGB888 像素数据
    wire        de;                                                         // 内部 wire：像素数据有效区
    wire        hs;                                                         // 内部 wire：行同步信号
    wire        vs;                                                         // 内部 wire：帧同步信号
    wire [31:0] display_frames;                                             // 内部 wire：HDMI 帧时序计数
    wire [31:0] display_underruns;                                          // 内部 wire：HDMI 显示缺行次数

    wire [319:0] shape_status;
    wire [31:0] captured;
    wire [11:0] camera_fps_bcd;
    v9_camera_fps camera_meter(clk_sys,rst_ui_n,captured,clk_pixel_2x,rst_pixel_n,camera_fps_bcd);
    v8_hdmi_display #(.FPS_ENABLE(1),.CAMERA_FPS_ENABLE(1)) screen (
        clk_pixel_2x,
        rst_pixel_n,
        line_in,
        line_in_valid,
        line_in_ready,
        display_out,
        display_out_valid,
        display_out_ready,
        rgb,
        de,
        hs,
        vs,
        display_frames,
        display_underruns,shape_control,shape_status,camera_fps_bcd
    );

    wire [23:0] diagnostic_rgb;
    wire diagnostic_de,diagnostic_hs,diagnostic_vs;
    v8_diagnostic_display diagnostic_screen(
        clk_pixel_2x,rst_pixel_n,diag_mode,rgb,de,hs,vs,
        diagnostic_rgb,diagnostic_de,diagnostic_hs,diagnostic_vs,diag_active_mode);
    assign hdmi_txc_o                                                          = 10'b1111100000;
    assign {hdmi_txc_oe, hdmi_txd0_oe, hdmi_txd1_oe, hdmi_txd2_oe}             = 4'b1111;
    assign {hdmi_txc_rst_o, hdmi_txd0_rst_o, hdmi_txd1_rst_o, hdmi_txd2_rst_o} = {4{!rst_pixel_n}};

    tmds_channel #(0) tmds0 (
        clk_pixel_2x,
        diagnostic_rgb[7:0],
        4'b0,
        {diagnostic_vs, diagnostic_hs},
        {2'b0, diagnostic_de},
        hdmi_txd0_o
    );

    tmds_channel #(1) tmds1 (
        clk_pixel_2x,
        diagnostic_rgb[15:8],
        4'b0,
        2'b0,
        {2'b0, diagnostic_de},
        hdmi_txd1_o
    );

    tmds_channel #(2) tmds2 (
        clk_pixel_2x,
        diagnostic_rgb[23:16],
        4'b0,
        2'b0,
        {2'b0, diagnostic_de},
        hdmi_txd2_o
    );
    wire         wr_req;                                                    // 内部 wire：DDR 写突发请求
    wire         wr_accept;                                                 // 内部 wire：写命令已接收脉冲
    wire         wr_valid;                                                  // 内部 wire：写数据有效
    wire         wr_ready;                                                  // 内部 wire：写数据接收就绪
    wire         wr_done;                                                   // 内部 wire：写突发完成脉冲
    wire         wr_error;                                                  // 内部 wire：写突发错误标志
    wire         rd_req;                                                    // 内部 wire：DDR 读突发请求
    wire         rd_accept;                                                 // 内部 wire：读命令已接收脉冲
    wire         rd_valid;                                                  // 内部 wire：读数据有效
    wire         rd_ready;                                                  // 内部 wire：读数据接收就绪
    wire         rd_done;                                                   // 内部 wire：读突发完成脉冲
    wire         rd_error;                                                  // 内部 wire：读突发错误标志
    wire [ 31:0] wr_addr;                                                   // 内部 wire：DDR 写字节地址
    wire [ 31:0] rd_addr;                                                   // 内部 wire：DDR 读字节地址
    wire [  7:0] wr_len;                                                    // 内部 wire：写突发拍数减一
    wire [  7:0] rd_len;                                                    // 内部 wire：读突发拍数减一
    wire [127:0] wr_data;                                                   // 内部 wire：128 位写数据
    wire [127:0] rd_data;                                                   // 内部 wire：128 位读数据
    // captured declared above for the camera FPS meter;                                                  // 内部 wire：完整采集帧计数
    wire [ 31:0] processed;                                                 // 内部 wire：完整处理帧计数
    wire [ 31:0] discarded;                                                 // 内部 wire：丢弃帧计数
    wire [ 31:0] ddr_errors;                                                // 内部 wire：DDR 事务错误计数
    wire [ 15:0] state;                                                     // 内部 wire：DDR 帧调度状态供 Debugger 观测

    wire [223:0] performance;
    v8_frame_store #(.FAST_ENABLE(1)) frames (
        clk_sys,
        rst_ui_n,
        cal_done && cal_pass,
        cap_data,
        cap_valid,
        cap_ready,
        cap_level,
        result_data,
        result_valid,
        result_ready,
        result_level,
        raw_in,
        raw_in_valid,
        raw_in_ready,
        raw_level,
        display_in,
        display_in_valid,
        display_in_ready,
        display_level,
        line_request,
        line_valid,
        line_ready,
        cmd_in,
        cmd_in_valid,
        cmd_in_ready,
        threshold,
        median,
        wr_req,
        wr_addr,
        wr_len,
        wr_accept,
        wr_data,
        wr_valid,
        wr_ready,
        wr_done,
        wr_error,
        rd_req,
        rd_addr,
        rd_len,
        rd_accept,
        rd_data,
        rd_valid,
        rd_ready,
        rd_done,
        rd_error,
        captured,
        processed,
        discarded,
        ddr_errors,
        state,
        control_pressed[0],
        control_pressed[1],
        playback_mode,
        history_count,
        replay_remaining,
        history_busy,
        replay_waiting,
        canny_enable,threshold_low,color_enable,overlay_enable,compare_view,
        control_pressed[8],control_pressed[9],control_pressed[10],control_pressed[11],
        compare_active,selected_b,compare_index_a,compare_index_b,canny_passes,performance
    );

    axi_burst_bridge bridge (
        clk_sys,
        rst_ui_n,
        wr_req,
        wr_addr,
        wr_len,
        wr_accept,
        wr_data,
        wr_valid,
        wr_ready,
        wr_done,
        wr_error,
        rd_req,
        rd_addr,
        rd_len,
        rd_accept,
        rd_data,
        rd_valid,
        rd_ready,
        rd_done,
        rd_error,
        axi_aid,
        axi_aaddr,
        axi_alen,
        axi_asize,
        axi_aburst,
        axi_alock,
        axi_avalid,
        axi_aready,
        axi_atype,
        axi_wid,
        axi_wdata,
        axi_wstrb,
        axi_wlast,
        axi_wvalid,
        axi_wready,
        axi_rid,
        axi_rdata,
        axi_rlast,
        axi_rvalid,
        axi_rready,
        axi_rresp,
        axi_bid,
        axi_bresp,
        axi_bvalid,
        axi_bready
    );

    assign clk_p_hi   = 0;
    assign clk_p_lo   = 1;
    assign clk_n_hi   = 1;
    assign clk_n_lo   = 0;
    assign o_dqs_n_oe = o_dqs_oe;
    assign shift_sel  = 5'b00100;
    assign addr       = ddr_addr[14:0];
    reg [25:0] heartbeat = 0;                                               // 内部 reg：系统时钟心跳分频计数

    always @(posedge clk_sys) heartbeat <= heartbeat + 1'b1;

    assign led_o = {~ddr_errors[0], ~i2c_done, ~processed[5], ~heartbeat[25], cal_pass, cal_done};
    // 官方 DDR3 Soft Controller：16 位物理数据、128 位 AXI 用户数据。
    DdrCtrl memory_controller (
        .clk          (clk_sys),
        .core_clk     (core_clk),
        .twd_clk      (twd_clk),
        .tdqss_clk    (tdqss_clk),
        .tac_clk      (tac_clk),
        .reset_n      (rst_ui_n),
        .reset        (reset),
        .cs           (cs),
        .ras          (ras),
        .cas          (cas),
        .we           (we),
        .cke          (cke),
        .addr         (ddr_addr),
        .ba           (ba),
        .odt          (odt),
        .shift        (shift),
        .shift_sel    (),
        .shift_ena    (shift_ena),
        .cal_ena      (1'b1),
        .cal_done     (cal_done),
        .cal_pass     (cal_pass),
        .cal_shift_val(cal_shift_val),
        .o_dm_hi      (o_dm_hi),
        .o_dm_lo      (o_dm_lo),
        .i_dqs_hi     (i_dqs_hi),
        .i_dqs_lo     (i_dqs_lo),
        .i_dqs_n_hi   (2'b0),
        .i_dqs_n_lo   (2'b0),
        .o_dqs_hi     (o_dqs_hi),
        .o_dqs_lo     (o_dqs_lo),
        .o_dqs_n_hi   (),
        .o_dqs_n_lo   (),
        .o_dqs_oe     (o_dqs_oe),
        .o_dqs_n_oe   (),
        .i_dq_hi      (i_dq_hi),
        .i_dq_lo      (i_dq_lo),
        .o_dq_hi      (o_dq_hi),
        .o_dq_lo      (o_dq_lo),
        .o_dq_oe      (o_dq_oe),
        .axi_aid      (axi_aid),
        .axi_aaddr    (axi_aaddr),
        .axi_alen     (axi_alen),
        .axi_asize    (axi_asize),
        .axi_aburst   (axi_aburst),
        .axi_alock    (axi_alock),
        .axi_avalid   (axi_avalid),
        .axi_aready   (axi_aready),
        .axi_atype    (axi_atype),
        .axi_wid      (axi_wid),
        .axi_wdata    (axi_wdata),
        .axi_wstrb    (axi_wstrb),
        .axi_wlast    (axi_wlast),
        .axi_wvalid   (axi_wvalid),
        .axi_wready   (axi_wready),
        .axi_rid      (axi_rid),
        .axi_rdata    (axi_rdata),
        .axi_rlast    (axi_rlast),
        .axi_rvalid   (axi_rvalid),
        .axi_rready   (axi_rready),
        .axi_rresp    (axi_rresp),
        .axi_bid      (axi_bid),
        .axi_bresp    (axi_bresp),
        .axi_bvalid   (axi_bvalid),
        .axi_bready   (axi_bready),
        .cal_fail_log (cal_fail_log)
    );
    // Efinity Debugger：VIO 状态观测与两组逻辑分析仪，必须匹配本版 profile。
    edge_debug edge_debug_inst (
        .shapes_clk(clk_pixel_2x),
        .shapes_snapshot({6'd0,shape_status[297:288],controls_telemetry[15:0],shape_status[287:0]}),
        .bscan_CAPTURE       (jtag_inst1_CAPTURE),
        .bscan_DRCK          (jtag_inst1_DRCK),
        .bscan_RESET         (jtag_inst1_RESET),
        .bscan_RUNTEST       (jtag_inst1_RUNTEST),
        .bscan_SEL           (jtag_inst1_SEL),
        .bscan_SHIFT         (jtag_inst1_SHIFT),
        .bscan_TCK           (jtag_inst1_TCK),
        .bscan_TDI           (jtag_inst1_TDI),
        .bscan_TMS           (jtag_inst1_TMS),
        .bscan_UPDATE        (jtag_inst1_UPDATE),
        .bscan_TDO           (jtag_inst1_TDO),
        .status_clk          (clk_sys),
        .status_clocks       ({1'b0, video_pll_lock, ddr_pll_lock, sys_pll_lock}),
        .status_ddr_cal      ({cal_done, cal_pass}),
        .status_i2c_done     (i2c_done),
        .status_i2c_nacks    (i2c_nacks),
        .status_i2c_index    (i2c_index),
        .status_captured     (captured),
        .status_processed    (processed),
        .status_discarded    (discarded),
        .status_ddr_errors   (ddr_errors),
        .status_state        (state),
        .status_cap_level    (cap_level),
        .status_raw_level    (raw_level),
        .status_result_level (result_level),
        .status_display_level(display_level),
        .status_matrix_keys(matrix_stable),
        .status_matrix_rows(key_row),
        .status_matrix_cols(key_col_in),
        .status_matrix_oe(key_col_oe),
        .status_matrix_multi(matrix_multi),
        .status_matrix_armed(matrix_armed),
        .status_playback_mode(playback_mode),
        .status_history_count(history_count),
        .status_replay_remaining(replay_remaining),
        .status_history_busy(history_busy),
        .status_replay_waiting(replay_waiting),
        .status_threshold    (threshold),
        .status_median       (median),
        .status_canny        (canny_enable),
        .status_canny_passes (canny_passes),
        .status_color        (color_enable),
        .status_compare      (compare_active),
        .status_selected_b   (selected_b),
        .status_index_a      (compare_index_a),
        .status_index_b      (compare_index_b),
        .status_compare_edge (compare_edge),
        .status_compare_view (compare_view),
        .status_display_sample(display_sample),
        .performance_clk(clk_sys),
        .performance_counters(performance),
        .white_balance_clk   (clk_pixel_2x),
        .white_balance_config_word(wb_config),
        .white_balance_applied(wb_applied),
        .white_balance_ack   (wb_ack),
        .white_balance_snapshot(wb_snapshot),
        .diagnostic_clk      (clk_pixel_2x),
        .diagnostic_request  (diag_request),
        .diagnostic_mode     (diag_mode),
        .diagnostic_ack      (diag_ack),
        .diagnostic_snapshot (diag_snapshot),
        .diagnostic_active_mode(diag_active_mode),
        .test_clk            (clk_sys),
        .test_keys           (debug_keys),
        .sample_clk          (clk_sys),
        .sample_address      (sample_address),
        .sample_a            (sample_a),
        .sample_b            (sample_b),
        .sample_header_a     (sample_header_a),
        .sample_header_b     (sample_header_b),
        .sample_seq_a        (sample_seq_a),
        .sample_seq_b        (sample_seq_b),
        .camera_clk          (rx_clk),
        .camera_frames       (camera_frames),
        .camera_overflow     (camera_overflow),
        .camera_format_errors(camera_format_errors),
        .camera_vs           (rx_vs[0]),
        .camera_de           (rx_de),
        .camera_line_words   (camera_line_words),
        .camera_frame_words  (camera_frame_words),
        .display_clk         (clk_pixel_2x),
        .display_frames      (display_frames),
        .display_underruns   (display_underruns)
    );
    // Same UI clock domain as controls, playback and committed-result counters.
    // During playback history_count is fixed; count-remaining is a 1-based ordinal.
    // Logical digits run left-to-right; ATK physical order is CH4..CH1.
    // Pure wire permutation retains the verified formatter/scanner unchanged.
    wire [3:0] seg_scan_select;
    assign seg_sel_o={seg_scan_select[0],seg_scan_select[1],seg_scan_select[2],seg_scan_select[3]};
    v8_sevenseg_status sevenseg (
        .clk(clk_sys), .rst_n(rst_ui_n),
        .ready(cal_done && cal_pass && i2c_done && processed!=0),
        .playback_mode(playback_mode), .compare_active(compare_active), .selected_b(selected_b),
        .index_a(compare_index_a), .index_b(compare_index_b),
        .history_count(history_count), .replay_remaining(replay_remaining),
        .canny_enable(canny_enable), .median_enable(median), .color_enable(color_enable),
        .overlay_enable(overlay_enable), .select_low(select_low),
        .threshold_high(threshold), .threshold_low(threshold_low),
        .compare_view(compare_view), .shape_control(shape_control),
        .seg_o(seg_o), .seg_sel_o(seg_scan_select), .shown_ascii()
    );
endmodule
