`timescale 1ns / 1ps

// ============================================================================
// 1080p60 显示：2200×1125 总时序、1920×1080 有效区，像素时钟 148.5 MHz。
// 左右各显示完整场景的 960×540 图像，纵向 270～809 行，其他区域黑色。
// 四行 RAM 环形、提前两行预取；吸收32位A/B读双倍带宽下的DDR突发延迟。
// 检测缺行并计数，启动阶段等待首行时不计欠载。
// ============================================================================
module v8_hdmi_display #(
    parameter FPS_ENABLE=0,
    parameter CAMERA_FPS_ENABLE=0,
    parameter FPS_CLK_HZ=148500000
) (
    input              clk,                                                 // 输入：本模块工作时钟
    input              rst_n,                                               // 输入：低有效复位
    output reg [  9:0] line_request,                                        // 输出：待预取的缩小图像行号
    output reg         line_valid,                                          // 输出：行请求有效
    input              line_ready,                                          // 输入：行请求接收就绪
    input      [151:0] data,                                                // {侧,模式,行,字,像素数据}
    input              valid,                                               // 输入：数据有效
    output             ready,                                               // 输出：允许接收数据
    output reg [ 23:0] rgb,                                                 // 输出：RGB888 像素数据
    output reg         de,                                                  // 输出：像素数据有效区
    output reg         hs,                                                  // 输出：行同步信号
    output reg         vs,                                                  // 输出：帧同步信号
    output reg [ 31:0] frame_count,                                         // 输出：帧计数
    output reg [ 31:0] underruns,                                           // 输出：显示欠载计数
    input [2:0] shape_control,
    output [319:0] shape_status,
    input [11:0] camera_fps_bcd
);
    reg [11:0] x;                                                           // 内部 reg：包含消隐区的光栅时序计数
    reg [10:0] y;                                                           // 内部 reg：包含消隐区的光栅时序计数
    reg [9:0] bank_row[0:7];                                                // 四行x两个比较帧
    reg [7:0] bank_valid;
    reg [4:0] bank_flags[0:3];
    reg line_good;                                                          // 内部 reg：当前显示行缓存命中
    reg have_image;                                                         // 内部 reg：至少收到过一条完整图像行
    wire viewing = y >= 270 && y < 810;                                     // 内部 wire：纵向处于 540 行图像区
    wire [9:0] scene_y = y - 270;                                           // 内部 wire：半屏场景行坐标
    wire [10:0] scene_x = x < 960 ? x : x - 960;                            // 内部 wire：左右半屏共用的场景列坐标
    wire [10:0] read_address = {
        scene_y[1:0], (bank_flags[scene_y[1:0]][3] && x>=960), scene_x[9:2]
    };                                                                      // 内部 wire：奇偶行选择及行内读字地址
    wire [7:0] write_index=data[135:128];
    wire [10:0] write_address = {
        data[137:136], data[151], write_index
    };                                                                      // 内部 wire：由显示包行号和字序号构成的写地址
    wire [31:0] q[0:3];                                                     // 四个32位像素并行RAM
    genvar b;
    // 实时/历史格式相同，每拍4x32位；历史保留RGB565、边缘和原灰度。
    generate
        for (b = 0; b < 4; b = b + 1) begin : bank
            (* ram_style="block" *) reg [31:0] mem[0:2047];
            reg [31:0] qr;
            wire [31:0] write_pixel=data[b*32+:32];

            always @(posedge clk) begin
                if (valid) mem[write_address] <= write_pixel;
                qr <= mem[read_address];
            end

            assign q[b] = qr;
        end
    endgenerate
    reg [ 1:0] byte_sel;
    reg [4:0] flagsq;
    wire [31:0] selected_pixel=q[byte_sel];
    wire [15:0] color565=selected_pixel[31:16];
    wire [23:0] color888={color565[15:11],color565[15:13],color565[10:5],color565[10:9],color565[4:0],color565[4:2]};
    wire [2:0] bank_a={scene_y[1:0],1'b0},bank_b={scene_y[1:0],1'b1};
    wire row_good=bank_valid[bank_a] && bank_row[bank_a]==scene_y &&
        (!bank_flags[scene_y[1:0]][3] || (bank_valid[bank_b] && bank_row[bank_b]==scene_y));
    reg        dq;                                                          // 内部 reg：数据有效区延迟
    reg        hq;                                                          // 内部 reg：行同步延迟
    reg        vq;                                                          // 内部 reg：帧同步延迟
    reg        rightq;                                                      // 内部 reg：右半屏选择延迟
    reg        goodq;                                                       // 内部 reg：当前像素图像有效标志延迟
    reg [15:0] selected;                                                    // 内部 reg：第一版保留的未使用寄存器声明

    assign ready = 1'b1;

    // Shape analysis observes original gray, never its own colored annotation.
    // Control bus is synchronized and adopted only at a frame boundary.
    (* async_reg="true" *) reg [2:0] shape_meta,shape_sync;
    reg [2:0] shape_config;
    reg [11:0] raster_xq;
    reg [10:0] raster_yq;
    wire shape_begin=raster_xq==0 && raster_yq==270;
    wire shape_end=raster_xq==959 && raster_yq==809;
    wire [9:0] sample_y=raster_yq-270;
    wire [7:0] shape_threshold=8'd80+{shape_config[2:1],5'b0};
    // The first pixel belongs to the newly latched frame configuration.
    wire shape_sample=dq && goodq && !rightq && !flagsq[3] && (shape_begin?shape_sync[0]:shape_config[0]);
    reg [7:0] shape_end_pipe;
    wire [227:0] detected_boxes;
    wire shape_valid,shape_overflow,shape_busy;
    wire [31:0] shape_completed;
    wire [21:0] shape_cycles;
    wire [9:0] shape_diagnostics;
    reg [227:0] visible_boxes;
    reg visible_valid;
    wire edge_valid,edge_pixel;
    v8_shape_edges shape_edges(clk,rst_n,shape_begin,shape_sample,selected_pixel[7:0],shape_config[2:1],raster_xq[9:0],sample_y,edge_valid,edge_pixel);
    wire [227:0] tracked_boxes;
    wire tracked_valid;
    reg [31:0] completed_q;
    wire tracker_clear=shape_begin && (!shape_config[0] || shape_config!=shape_sync || flagsq[3] || !shape_valid || shape_busy || shape_overflow);
    v8_shape_tracker shape_tracker(clk,rst_n,shape_completed!=completed_q,tracker_clear,detected_boxes,tracked_boxes,tracked_valid);
    assign shape_status={22'd0,shape_diagnostics,shape_config,visible_valid,shape_busy,shape_overflow,shape_cycles,shape_completed,visible_boxes};
    v8_shape_detector shape_detector(clk,rst_n,shape_begin,shape_end_pipe[7],
        edge_valid,edge_pixel,
        detected_boxes,shape_valid,shape_overflow,shape_busy,shape_completed,shape_cycles,shape_diagnostics);
    wire shape_hit;
    wire [23:0] shape_rgb;
    wire fps_hit;
    wire [23:0] fps_rgb;
    generate if(FPS_ENABLE) begin : fps_status
        reg [27:0] first_row_tag;
        wire [11:0] sampled_bcd;
        wire [11:0] displayed_bcd=CAMERA_FPS_ENABLE?camera_fps_bcd:sampled_bcd;
        reg [11:0] visible_bcd;
        wire [31:0] presented_frames;
        wire left_area=dq && raster_xq<960 && raster_yq>=270 && raster_yq<810;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin first_row_tag<=0;visible_bcd<=0;end
            else begin
                if(valid && !data[151] && data[145:136]==0 && write_index==0)
                    first_row_tag<={data[111:105],data[79:73],data[47:41],data[15:9]};
                // Atomic text update before the status row, once per raster.
                if(raster_xq==0 && raster_yq==0) visible_bcd<=displayed_bcd;
            end
        end
        v9_presented_fps #(.CLK_HZ(FPS_CLK_HZ)) meter(
            clk,rst_n,dq && shape_begin,dq && shape_end,
            left_area && !goodq,first_row_tag,sampled_bcd,presented_frames);
        v9_fps_overlay label(raster_xq,raster_yq,visible_bcd,fps_hit,fps_rgb);
    end else begin : no_fps_status
        assign fps_hit=1'b0;assign fps_rgb=24'd0;
    end endgenerate
    v8_shape_overlay shape_overlay(raster_xq,raster_yq,
        shape_config[0] && (raster_yq<270 || !flagsq[3]),
        visible_valid && goodq,shape_overflow,shape_config[2:1],visible_boxes,shape_hit,shape_rgb);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            shape_meta<=0;shape_sync<=0;shape_config<=0;
            raster_xq<=0;raster_yq<=0;visible_boxes<=0;visible_valid<=0;completed_q<=0;shape_end_pipe<=0;
        end else begin
            shape_meta<=shape_control;shape_sync<=shape_meta;
            completed_q<=shape_completed;
            shape_end_pipe<={shape_end_pipe[6:0],shape_end};
            raster_xq<=x;raster_yq<=y;
            if(shape_begin) begin
                shape_config<=shape_sync;visible_boxes<=tracked_boxes;
                visible_valid<=tracked_valid && shape_valid && !shape_busy && !shape_overflow && shape_config==shape_sync && !flagsq[3];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x            <= 0;
            y            <= 0;
            line_valid   <= 0;
            line_request <= 0;
            bank_valid   <= 0;
            bank_flags[0]<=0;bank_flags[1]<=0;bank_flags[2]<=0;bank_flags[3]<=0;flagsq<=0;
            line_good    <= 0;
            have_image   <= 0;
            dq           <= 0;
            hq           <= 0;
            vq           <= 0;
            rightq       <= 0;
            goodq        <= 0;
            byte_sel     <= 0;
            rgb          <= 0;
            de           <= 0;
            hs           <= 0;
            vs           <= 0;
            frame_count  <= 0;
            underruns    <= 0;
        end
        else begin
            // 总时序 2200×1125；图像区以外输出黑色，同步信号保持标准时序。
            if (x == 2199) begin
                x <= 0;
                if (y == 1124) begin
                    y           <= 0;
                    frame_count <= frame_count + 1'b1;
                end
                else y <= y + 1'b1;
            end
            else x <= x + 1'b1;
            if (line_valid && line_ready) line_valid <= 0;
            if (x == 0 && y >= 268 && y < 808) begin
                if (!line_valid || line_ready) begin
                    line_request <= y - 268;
                    line_valid   <= 1;
                end
                else underruns <= underruns + 1'b1;
            end
            if (valid) begin
                if (write_index == 0) begin
                    bank_valid[{data[137:136],data[151]}] <= 0;
                    // A开始新行时同时撤销旧B，避免B长时间缺失后同一行号跨帧误命中。
                    if(!data[151]) bank_valid[{data[137:136],1'b1}]<=0;
                end
                if (write_index == 239) begin
                    bank_valid[{data[137:136],data[151]}] <= 1;
                    bank_row[{data[137:136],data[151]}] <= data[145:136];
                    bank_flags[data[137:136]]<=data[150:146];
                    have_image            <= 1;
                end
            end
            if (x == 0 && viewing) begin
                line_good <= row_good;
                if (have_image && !row_good)
                    underruns <= underruns + 1'b1;
            end
            byte_sel <= scene_x[1:0];
            flagsq<=bank_flags[scene_y[1:0]];
            rightq <= x >= 960;
            dq <= x < 1920 && y < 1080;
            hq <= x >= 2008 && x < 2052;
            vq <= y >= 1084 && y < 1089;
            goodq<=viewing&&(x==0?row_good:line_good);
            de <= dq;
            hs <= hq;
            vs <= vq;
            if(dq && fps_hit) rgb<=fps_rgb;
            else if(dq && shape_hit) rgb<=shape_rgb;
            else if (dq && goodq) begin
                if(flagsq[3]) rgb<=flagsq[4]?{24{selected_pixel[8]}}:
                                   flagsq[0]?color888:{3{selected_pixel[7:0]}};
                else if(rightq) rgb<={24{selected_pixel[8]}};
                else if(!flagsq[2] && flagsq[1] && selected_pixel[8]) rgb<=24'hff0000;
                else if(flagsq[0]) rgb<=color888;
                else rgb<={3{selected_pixel[7:0]}};
            end
            else rgb <= 0;
        end
    end
endmodule
