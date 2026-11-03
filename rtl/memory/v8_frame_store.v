`timescale 1ns / 1ps

// ============================================================================
// V8 DDR 调度：RAW/32位实时结果三缓冲、32位完整历史、A/B比较和Canny多阶段。
// 每16拍实时突发镜像为16拍历史突发；Canny中间帧不进入历史，只提交收敛后的结果。
// 按 FIFO 水位预留完整突发；完整帧成功写回后才发布，显示帧槽在行 0 请求时切换。
// 截断采集帧补零结束当前突发后丢弃，保留下一帧首包用于恢复。
// ============================================================================
module v8_frame_store #(
    parameter HISTORY_FRAMES = 232,
    parameter RAW_WORDS = 129600,                                          // RAW 每帧 128 位字数，必须为 16 的倍数
    parameter RESULT_WORDS = 129600,                                       // V8每结果像素32位，4像素/字
    parameter ROW_WORDS = 240,                                              // 实时/历史每行均240字
    parameter FAST_ENABLE = 0,
    parameter FRAME_TAG_ENABLE = 0
) (
    input              clk,                                                 // 输入：本模块工作时钟
    input              rst_n,                                               // 输入：低有效复位
    input              enable,                                              // 输入：功能使能
    input      [145:0] cap_data,                                            // 输入：带序号及错误位的采集包
    input              cap_valid,                                           // 输入：采集包有效
    output             cap_ready,                                           // 输出：采集包接收就绪
    input      [ 11:0] cap_level,                                           // 输入：采集 FIFO 当前水位
    input      [127:0] result_data,                                         // 输入：128 位结果数据
    input              result_valid,                                        // 输入：结果数据有效
    output             result_ready,                                        // 输出：结果接收就绪
    input      [ 10:0] result_level,                                        // 输入：结果 FIFO 当前水位
    output     [127:0] raw_data,                                            // 输出：RAW 像素数据
    output             raw_valid,                                           // 输出：RAW 数据有效
    input              raw_ready,                                           // 输入：RAW 接收就绪
    input      [ 10:0] raw_level,                                           // 输入：RAW FIFO 当前水位
    output     [151:0] display_data,                                        // {侧,显示模式5位,行10位,字8位,数据128位}
    output             display_valid,                                       // 输出：显示包有效
    input              display_ready,                                       // 输入：显示包接收就绪
    input      [  9:0] display_level,                                       // 输入：显示 FIFO 当前水位
    input      [  9:0] line_request,                                        // 输入：待预取的缩小图像行号
    input              line_valid,                                          // 输入：行请求有效
    output             line_ready,                                          // 输出：行请求接收就绪
    output     [ 25:0] command,                                             // 阶段2位、中值、低阈值11位、高阈值11位
    output             command_valid,                                       // 输出：帧命令有效
    input              command_ready,                                       // 输入：帧命令接收就绪
    input      [ 10:0] threshold,                                           // 输入：边缘判决阈值
    input              median_enable,                                       // 输入：中值滤波使能，高有效
    output             wr_req,                                              // 输出：DDR 写突发请求
    output     [ 31:0] wr_addr,                                             // 输出：DDR 写字节地址
    output     [  7:0] wr_len,                                              // 输出：写突发拍数减一
    input              wr_accept,                                           // 输入：写命令已接收脉冲
    output     [127:0] wr_data,                                             // 输出：128 位写数据
    output             wr_valid,                                            // 输出：写数据有效
    input              wr_ready,                                            // 输入：写数据接收就绪
    input              wr_done,                                             // 输入：写突发完成脉冲
    input              wr_error,                                            // 输入：写突发错误标志
    output             rd_req,                                              // 输出：DDR 读突发请求
    output     [ 31:0] rd_addr,                                             // 输出：DDR 读字节地址
    output     [  7:0] rd_len,                                              // 输出：读突发拍数减一
    input              rd_accept,                                           // 输入：读命令已接收脉冲
    input      [127:0] rd_data,                                             // 输入：128 位读数据
    input              rd_valid,                                            // 输入：读数据有效
    output             rd_ready,                                            // 输出：读数据接收就绪
    input              rd_done,                                             // 输入：读突发完成脉冲
    input              rd_error,                                            // 输入：读突发错误标志
    output reg [ 31:0] captured,                                            // 输出：完整采集帧计数
    output reg [ 31:0] processed,                                           // 输出：完整处理帧计数
    output reg [ 31:0] discarded,                                           // 输出：丢弃帧计数
    output reg [ 31:0] ddr_errors,                                          // 输出：DDR 事务错误计数
    output     [ 15:0] state_debug,                                         // 输出：帧槽与调度状态打包供调试
    input              freeze_press,                                       // 输入：冻结键单周期脉冲
    input              replay_press,                                       // 输入：回放键单周期脉冲
    output     [  1:0] playback_mode,                                      // 输出：0实时/1冻结/2回放/3暂停
    output     [  8:0] history_count,                                      // 输出：已提交历史帧数
    output     [  8:0] replay_remaining,                                   // 输出：当前帧之后未播放帧数
    output             history_busy,                                       // 输出：历史录制收尾中
    output             replay_waiting,                                     // 输出：等待历史录制收尾后进入回放
    input canny_enable, input [10:0] threshold_low,
    input color_enable,overlay_enable,input [1:0] compare_view,
    input compare_press,select_press,prev_press,next_press,
    output compare_active,selected_b,output [8:0] index_a,index_b,
    output reg [31:0] canny_passes,output [223:0] performance
);
    localparam [31:0] HISTORY_BASE = 32'h02000000;                          // 历史区：32 MiB起，每槽2 MiB，共232槽，止于496 MiB
    reg [31:0] display_base;                                               // 内部：整幅显示期间保持不变的 DDR 基地址
    reg [31:0] display_base_b;
    reg [4:0] display_flags;
    // V9: stable source identity for the selected LEFT scene. Live result slots
    // rotate, so compare the commit sequence, never just the physical address.
    reg [27:0] display_frame_tag;
    reg row_side;
    reg [1:0] phase;
    reg fast_mode,fast_overflow;
    reg [31:0] fast_frames,fallback_frames;
    reg [31:0] prep_cycles,final_cycles,legacy_cycles;
    localparam FAST_WORDS=RAW_WORDS*3;
    reg scratch_bank,pass_changed;
    reg sweep_reverse;
    wire reverse_scan=phase==2 && sweep_reverse;
    localparam SCRATCH_WORDS=RAW_WORDS*4;
    wire final_phase=phase==0 || phase==3;
    wire [19:0] input_words=phase<2?RAW_WORDS:(fast_mode?FAST_WORDS:SCRATCH_WORDS);
    wire [19:0] output_words=final_phase?RESULT_WORDS:(fast_mode?FAST_WORDS:SCRATCH_WORDS);
    wire [31:0] scratch_read_base=scratch_bank?32'h1f800000:32'h1f000000;
    wire [31:0] scratch_write_base=phase==1?32'h1f000000:
                                   (scratch_bank?32'h1f000000:32'h1f800000);
    reg        record_this_frame;                                          // 内部：当前结果帧是否同时录制
    reg [8:0]  record_frame_slot;                                          // 内部：当前预约的历史写槽
    reg        history_pending;                                            // 内部：实时突发完成，等待镜像写入历史区
    reg        whistory;                                                   // 内部：当前写事务属于历史镜像
    reg [127:0] record_words[0:15];                                        // 保存完整RGB565/边缘/灰度，不额外回读DDR
    wire       record_frame;                                               // 内部：允许新帧进入历史区
    wire [8:0] record_slot;                                                // 内部：控制器给出的预约槽
    wire       view_history;                                               // 内部：本显示帧选择历史区
    wire       hold_live;                                                  // 内部：本显示帧保持实时画面
    wire [8:0] view_slot;                                                  // 内部：本显示帧历史槽
    wire [8:0] view_slot_b;
    wire view_compare;
    reg [ 1:0] raw_latest;                                                  // 内部 reg：最新完整 RAW 帧槽
    reg [ 1:0] raw_write_slot;                                              // 内部 reg：当前采集写入帧槽
    reg [ 1:0] raw_read_slot;                                               // 内部 reg：当前算法读取帧槽
    reg [ 1:0] result_latest;                                               // 内部 reg：最新完整结果帧槽
    reg [ 1:0] result_write_slot;                                           // 内部 reg：当前算法结果写入帧槽
    reg [ 1:0] display_slot;                                                // 内部 reg：当前显示持有的结果帧槽
    reg        raw_latest_valid;                                            // 内部 reg：存在待处理完整 RAW 帧
    reg        result_latest_valid;                                         // 内部 reg：存在可显示完整结果帧
    reg        raw_writing;                                                 // 内部 reg：采集帧写入进行中
    reg        processing;                                                  // 内部 reg：整帧算法处理进行中
    reg        raw_reading;                                                 // 内部 reg：向算法搬运 RAW 帧进行中
    reg        result_writing;                                              // 内部 reg：算法结果写入进行中
    reg        display_has_frame;                                           // 内部 reg：显示端已获得完整结果帧
    reg [17:0] cap_index;                                                   // 内部 reg：采集帧内 128 位字序号
    reg [19:0] raw_index;                                                   // RAW/中间帧读取字序号
    reg [19:0] result_index;                                                // 结果/中间帧写入字序号
    reg        cap_bad;                                                     // 内部 reg：当前采集帧已发生错误
    reg        result_bad;                                                  // 内部 reg：当前结果帧已发生错误
    reg        wbusy;                                                       // 内部 reg：写突发进行中
    reg        wowner;                                                      // 内部 reg：写突发来源：1 结果，0 采集
    reg        rbusy;                                                       // 内部 reg：读突发进行中
    reg        row_active;                                                  // 内部 reg：显示行搬运进行中
    reg        row_blank;                                                   // 内部 reg：尚无显示帧，本行请求不发 DDR 读取
    reg        read_owner;                                                  // 内部 reg：读突发去向：1 算法，0 显示
    reg        prefer_result;                                               // 内部 reg：写仲裁轮转优先结果
    reg        prefer_raw;                                                  // 内部 reg：读仲裁轮转优先 RAW
    reg [ 4:0] wbeat;                                                       // 内部 reg：写突发拍计数，保留第一版逻辑
    reg [ 7:0] rbeat;                                                       // 内部 reg：读突发拍计数，保留第一版逻辑
    reg [ 9:0] row;                                                         // 内部 reg：当前请求的缩小图像行
    reg [ 7:0] row_index;                                                   // 每行最多240个128位字
    reg [25:0] command_reg;                                                 // 帧参数及当前处理阶段
    reg        command_pending;                                             // 内部 reg：帧算法命令等待接收
    assign performance={29'd0,processing,phase,legacy_cycles,final_cycles,prep_cycles,fallback_frames,fast_frames,processed};
    wire result_start = enable && !processing && raw_latest_valid && !command_pending;
    wire stage_finish=enable && wr_done && wowner &&
                      (!final_phase || !record_this_frame || whistory) && result_index==output_words;
    wire result_finish=stage_finish && (final_phase || result_bad || wr_error);
    wire result_success = !result_bad && !wr_error;
    v8_playback_control #(HISTORY_FRAMES) playback (
        .clk(clk), .rst_n(rst_n), .freeze_press(freeze_press), .replay_press(replay_press),
        .compare_press(compare_press),.select_press(select_press),.prev_press(prev_press),.next_press(next_press),
        .frame_boundary(enable && line_valid && line_ready && line_request == 0),
        .display_available(display_has_frame), .result_start(result_start),
        .result_finish(result_finish), .result_success(result_success),
        .record_frame(record_frame), .record_slot(record_slot), .record_busy(history_busy),
        .history_count(history_count), .mode(playback_mode), .view_history(view_history),
        .hold_live(hold_live), .view_slot(view_slot), .replay_remaining(replay_remaining),
        .replay_waiting(replay_waiting),.view_compare(view_compare),.view_slot_b(view_slot_b),
        .selected_b(selected_b),.index_a(index_a),.index_b(index_b)
    );
    assign compare_active=display_flags[3];
    function [1:0] free_slot(input [1:0] a, b);
        begin
            if (a != 0 && b != 0) free_slot = 0;

            else if (a != 1 && b != 1) free_slot = 1;
            else free_slot = 2;
        end
    endfunction
    wire [16:0] packet_index = cap_data[144:128];                           // 内部 wire：采集包携带的帧内序号
    wire cap_candidate=raw_writing&&cap_valid&&(cap_level>=16);             // 内部 wire：采集水位足够一个写突发
    wire [127:0] reverse_raw,reverse_result;
    wire reverse_raw_valid,reverse_raw_ready,reverse_raw_empty;
    wire reverse_result_valid,reverse_result_ready;
    wire [127:0] result_payload=reverse_scan?reverse_result:result_data;
    v8_burst_reverse read_reverse(clk,rst_n,rd_data,
        rd_valid && rbusy && read_owner && reverse_scan,reverse_raw_ready,
        reverse_raw,reverse_raw_valid,raw_ready,reverse_raw_empty);
    v8_burst_reverse write_reverse(clk,rst_n,result_data,
        result_valid && result_writing && reverse_scan,reverse_result_ready,
        reverse_result,reverse_result_valid,wbusy && wowner && !whistory && wr_ready && reverse_scan,);
    wire res_candidate=result_writing&&!history_pending&&
        (reverse_scan?reverse_result_valid:(result_level>=16));
    wire choose_history=history_pending&&(!cap_candidate||prefer_result);    // 内部：历史写与摄像头公平轮转
    wire choose_result=!history_pending&&res_candidate&&(!cap_candidate||prefer_result);      // 内部 wire：本次写仲裁选择结果
    // 写调度：水位满足完整突发才请求，降低中途断流风险。
    assign wr_req = enable && !wbusy && (choose_history || choose_result || cap_candidate);
    assign wr_len = 8'd15;
    assign wr_addr=choose_history?(HISTORY_BASE+{2'b0,record_frame_slot,21'b0}+((result_index-20'd16)<<4)):
                   choose_result?((final_phase?(32'h1000000+{9'b0,result_write_slot,21'b0}):scratch_write_base)+
                                  ((reverse_scan?(SCRATCH_WORDS-result_index-20'd16):result_index)<<4)):
                              ({8'b0,raw_write_slot,22'b0}+{10'b0,cap_index,4'b0});
    // 包序号不连续时补零收尾当前突发，错误帧不发布。
    wire wrong_packet = (packet_index != cap_index[16:0]);                  // 内部 wire：采集包序号不连续

    assign wr_data = whistory ? record_words[wbeat[3:0]] : wowner ? result_payload : (wrong_packet ? 128'b0 : cap_data[127:0]);
    assign wr_valid = wbusy && (whistory || (wowner ? (reverse_scan?reverse_result_valid:result_valid) : cap_valid));
    assign result_ready = reverse_scan?(result_writing && reverse_result_ready):(wbusy && wowner && !whistory && wr_ready);
    assign cap_ready=(!raw_writing&&cap_valid&&packet_index!=0)||
                  (wbusy&&!wowner&&wr_ready&&!wrong_packet);
    wire raw_candidate=raw_reading&&(raw_level<=1000)&&(!reverse_scan || reverse_raw_empty);
    wire disp_candidate=row_active&&!row_blank&&(display_level<=256);       // 深512 FIFO预留完整最长256拍突发
    // 显示有硬性行截止时间；算法可以反压。整条显示行优先，不能与RAW逐突发轮转。
    // Canny持续读取中间帧时，旧轮转会使行请求落后光栅并产生整屏闪黑。
    // 已排队的行请求同样优先，避免行切换空档误启动16拍算法读。
    wire choose_raw=raw_candidate&&!disp_candidate&&!(line_valid && line_ready);
    // 读调度：先检查目标 FIFO 空间，读写各自独立推进。
    assign rd_req = enable && !rbusy && (choose_raw || disp_candidate);
    wire [8:0] row_words=ROW_WORDS;
    wire [31:0] display_address=(row_side?display_base_b:display_base)+
        row*(ROW_WORDS*16)+(row_index<<4);
    wire [8:0] row_remaining=row_words-row_index;
    wire [8:0] page_remaining=9'd256-{1'b0,display_address[11:4]};
    wire [8:0] display_burst=row_remaining;
    // 每行最多240拍，整行突发降低A/B双倍带宽的命令开销；必须在4KiB边界拆分。
    assign rd_len=choose_raw?8'd15:
        ((display_burst<page_remaining?display_burst:page_remaining)-9'd1);
    assign rd_addr=choose_raw?((phase<2?{8'b0,raw_read_slot,22'b0}:scratch_read_base)+
                              ((reverse_scan?(SCRATCH_WORDS-raw_index-20'd16):raw_index)<<4)):
        display_address;

    assign raw_data = reverse_raw_valid?reverse_raw:rd_data;
    assign raw_valid = reverse_raw_valid || (rd_valid && rbusy && read_owner && !reverse_scan);
    // 实时与历史统一4x32位/拍经过异步FIFO；历史标志只决定显示语义。
    // Four reserved [15:9] fields carry 28 bits in the first word of left row 0.
    // RGB565, edge and original gray stay byte-for-byte unchanged; FIFO width,
    // DDR layout, burst arbitration and processing backpressure are unchanged.
    wire tag_word=FRAME_TAG_ENABLE && !row_side && row==0 && row_index==0;
    wire [127:0] display_payload=tag_word?{
        rd_data[127:112],display_frame_tag[27:21],rd_data[104:96],
        rd_data[95:80],display_frame_tag[20:14],rd_data[72:64],
        rd_data[63:48],display_frame_tag[13:7],rd_data[40:32],
        rd_data[31:16],display_frame_tag[6:0],rd_data[8:0]}:rd_data;
    assign display_data={row_side,display_flags,row,row_index,display_payload};
    assign display_valid = rd_valid && rbusy && !read_owner;
    assign rd_ready=rbusy && (read_owner?(reverse_scan?reverse_raw_ready:raw_ready):display_ready);
    assign line_ready = !row_active;
    assign command = command_reg;
    assign command_valid = command_pending;
    assign state_debug = {
        canny_enable,phase,display_flags[3],
        raw_latest_valid,
        result_latest_valid,
        display_has_frame,
        raw_reading,
        raw_writing,
        result_writing,
        processing,
        row_active,
        wbusy,
        wowner,
        rbusy,
        read_owner
    };
    // 帧槽状态机：槽占用、完整帧发布及行请求处理均在同一时钟域。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_base        <= 0;
            display_base_b      <= 0;
            display_flags       <= 0;
            display_frame_tag   <= 0;
            row_side            <= 0;
            phase               <= 0;
            fast_mode<=0;fast_overflow<=0;fast_frames<=0;fallback_frames<=0;prep_cycles<=0;final_cycles<=0;legacy_cycles<=0;
            scratch_bank        <= 0;
            sweep_reverse       <= 0;
            pass_changed        <= 0;
            canny_passes        <= 0;
            record_this_frame   <= 0;
            record_frame_slot   <= 0;
            history_pending     <= 0;
            whistory            <= 0;
            raw_latest          <= 0;
            raw_write_slot      <= 1;
            raw_read_slot       <= 2;
            result_latest       <= 0;
            result_write_slot   <= 1;
            display_slot        <= 2;
            raw_latest_valid    <= 0;
            result_latest_valid <= 0;
            raw_writing         <= 0;
            processing          <= 0;
            raw_reading         <= 0;
            result_writing      <= 0;
            display_has_frame   <= 0;
            cap_index           <= 0;
            raw_index           <= 0;
            result_index        <= 0;
            cap_bad             <= 0;
            result_bad          <= 0;
            wbusy               <= 0;
            rbusy               <= 0;
            wowner              <= 0;
            read_owner          <= 0;
            row_active          <= 0;
            row_blank           <= 1;
            row                 <= 0;
            row_index           <= 0;
            wbeat               <= 0;
            rbeat               <= 0;
            command_pending     <= 0;
            command_reg         <= 0;
            prefer_result       <= 0;
            prefer_raw          <= 0;
            captured            <= 0;
            processed           <= 0;
            discarded           <= 0;
            ddr_errors          <= 0;
        end

        else if (enable) begin
            if(processing) begin
                if(phase==1) prep_cycles<=prep_cycles+1'b1;
                if(phase==2) legacy_cycles<=legacy_cycles+1'b1;
                if(phase==3) final_cycles<=final_cycles+1'b1;
            end
            if (command_pending && command_ready) command_pending <= 0;
            if (result_start) begin
                record_this_frame <= record_frame;
                record_frame_slot <= record_slot;
                processing        <= 1;
                raw_reading       <= 1;
                raw_read_slot     <= raw_latest;
                raw_index         <= 0;
                raw_latest_valid  <= 0;
                result_writing    <= 1;
                result_write_slot <= free_slot(result_latest, display_slot);
                result_index      <= 0;
                result_bad        <= 0;
                phase             <= canny_enable?1:0;
                fast_mode<=FAST_ENABLE && canny_enable;fast_overflow<=0;
                scratch_bank      <= 0;
                sweep_reverse     <= 0;
                pass_changed      <= 0;
                command_reg       <= {(FAST_ENABLE!=0 && canny_enable),canny_enable?2'd1:2'd0,median_enable,threshold_low,threshold};
                command_pending   <= 1;
            end
            if (!raw_writing && cap_valid && packet_index == 0) begin
                raw_writing    <= 1;
                raw_write_slot <= free_slot(raw_latest, raw_read_slot);
                cap_index      <= 0;
                cap_bad        <= 0;
            end
            if (wr_accept) begin
                wbusy         <= 1;
                wowner        <= choose_result || choose_history;
                whistory      <= choose_history;
                wbeat         <= 0;
                prefer_result <= !(choose_result || choose_history);
            end
            if (wr_valid && wr_ready) begin
                wbeat <= wbeat + 1'b1;
                if (wowner) begin
                    if (!whistory) begin
                        result_index <= result_index + 1'b1;
                        if(fast_mode && phase==1 && result_index==FAST_WORDS-1) fast_overflow<=result_payload[127];
                        if(record_this_frame && final_phase) record_words[wbeat[3:0]]<=result_data;
                        if(phase==2 && (result_payload[26] || result_payload[58] || result_payload[90] || result_payload[122]))
                            pass_changed<=1;
                    end
                end
                else begin
                    cap_index <= cap_index + 1'b1;
                    if (wrong_packet || cap_data[145]) cap_bad <= 1;
                end
            end
            if (wr_done) begin
                wbusy <= 0;
                if (wr_error) ddr_errors <= ddr_errors + 1'b1;
                if (wowner) begin
                    if (wr_error) result_bad <= 1;
                    if (whistory) history_pending <= 0;
                    else if (record_this_frame && final_phase) history_pending <= 1;
                    if(stage_finish && !result_finish) begin
                        // 当前整帧写完且响应成功，下一命令才读取已提交的中间帧。
                        if(fast_mode) begin
                            phase<=fast_overflow?1:3;
                            fast_mode<=!fast_overflow;
                            command_reg[25]<=!fast_overflow;
                            command_reg[24:23]<=fast_overflow?1:3;
                            scratch_bank<=0;sweep_reverse<=0;
                            if(fast_overflow) fallback_frames<=fallback_frames+1'b1;
                        end else begin
                        phase<=phase==1?2:(pass_changed?2:3);
                        scratch_bank<=phase==1?0:!scratch_bank;
                        // Reverse both read/write burst order and lane order: stored coordinates
                        // remain unchanged, so final scaling always reads normal raster order.
                        sweep_reverse<=phase==1?0:!sweep_reverse;
                        command_reg[24:23]<=phase==1?2:(pass_changed?2:3);
                        end
                        command_pending<=1;
                        raw_reading<=1;raw_index<=0;result_index<=0;pass_changed<=0;
                        if(phase==2) canny_passes<=canny_passes+1'b1;
                    end
                    // 必须等本帧最后一笔历史写响应成功后才发布和计数。
                    if (result_finish) begin
                        result_writing <= 0;
                        processing     <= 0;
                        if (!result_bad && !wr_error) begin
                            result_latest       <= result_write_slot;
                            result_latest_valid <= 1;
                            processed           <= processed + 1'b1;
                            if(fast_mode) fast_frames<=fast_frames+1'b1;
                        end
                        else discarded <= discarded + 1'b1;
                    end
                end
                else begin
                    if (wr_error) cap_bad <= 1;
                    if (cap_bad || wr_error || cap_index == RAW_WORDS) begin
                        raw_writing <= 0;
                        if (!cap_bad && !wr_error) begin
                            raw_latest       <= raw_write_slot;
                            raw_latest_valid <= 1;
                            captured         <= captured + 1'b1;
                        end
                        else discarded <= discarded + 1'b1;
                    end
                end
            end
            if (line_valid && line_ready) begin
                row       <= line_request;
                row_index <= 0;
                row_side<=0;
                if (line_request == 0) begin
                    display_flags<={compare_view==2,view_compare,view_history,overlay_enable,
                                    view_compare?(compare_view==1):color_enable};
                    if (view_history) begin
                        display_frame_tag <= {1'b1,18'd0,view_slot};
                        display_base      <= HISTORY_BASE + {2'b0,view_slot,21'b0};
                        display_base_b    <= HISTORY_BASE + {2'b0,view_slot_b,21'b0};
                        display_has_frame <= 1;
                        row_blank         <= 0;
                        row_active        <= 1;
                    end
                    else if (hold_live && display_has_frame) begin
                        // 冻结保持上一完整画面的地址；三缓冲分配继续保护该实时槽。
                        row_blank  <= 0;
                        row_active <= 1;
                    end
                    else if (result_latest_valid) begin
                        display_frame_tag <= {1'b0,processed[26:0]};
                        display_slot      <= result_latest;
                        display_base      <= 32'h01000000 + {9'b0,result_latest,21'b0};
                        display_has_frame <= 1;
                        row_blank         <= 0;
                        row_active        <= 1;
                    end
                    else begin
                        row_blank  <= 1;
                        row_active <= 0;
                    end
                end
                else begin
                    row_blank  <= !display_has_frame;
                    row_active <= display_has_frame;
                end
            end
            if (rd_accept) begin
                rbusy      <= 1;
                read_owner <= choose_raw;
                rbeat      <= 0;
                prefer_raw <= !choose_raw;
            end
            if (rd_valid && rd_ready) begin
                rbeat <= rbeat + 1'b1;
                if (read_owner) raw_index <= raw_index + 1'b1;
                else row_index <= row_index + 1'b1;
            end
            if (rd_done) begin
                rbusy <= 0;
                if (rd_error) begin
                    ddr_errors <= ddr_errors + 1'b1;
                    if (read_owner) result_bad <= 1;
                    else display_has_frame <= 0;
                end
                if (read_owner) begin
                    if (raw_index == input_words) raw_reading <= 0;
                end

                else if(row_index==row_words) begin
                    if(display_flags[3] && !row_side) begin row_side<=1;row_index<=0;end
                    else row_active<=0;
                end
            end
        end
    end
endmodule
