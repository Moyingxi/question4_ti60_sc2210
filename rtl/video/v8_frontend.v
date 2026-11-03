`timescale 1ns/1ps
// V8 全分辨率前端。五个 3x3 窗口：Bayer、中值、高斯、梯度、NMS。
// 全局 CE 支持反压；原灰度和 RGB565 与中心像素一起通过各级窗口。
// 输出 [23:8]=RGB565，[7:0]=原灰度，[24]=弱候选，[25]=强边缘。
module v8_frontend #(parameter WIDTH=1920, HEIGHT=1080, BAYER_PHASE=3,
    SOBEL_ENHANCE=1)(
    input clk, rst_n, start, canny, median_enable,
    input [10:0] threshold_low, threshold_high,
    input [7:0] raw_data, input raw_valid, output raw_ready,
    output [31:0] pixel, output pixel_valid, input pixel_ready,
    output pixel_last, output reg busy,
    input diag_request, output diag_ack, output [319:0] diag_snapshot,
    input [36:0] wb_config,output [36:0] wb_applied,
    output wb_ack,output [319:0] wb_snapshot
);
    reg [36:0] wb_frame;
    reg diag_frame_request;
    assign wb_applied=wb_frame;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin wb_frame<={1'b0,12'd256,12'd256,12'd256};diag_frame_request<=0;end
        else if(start && !busy) begin wb_frame<=wb_config;diag_frame_request<=diag_request;end
    reg feeding, canny_f, median_f;
    reg [10:0] low_f, high_f;
    reg [11:0] px,py;
    wire ce=!pixel_valid || pixel_ready;
    wire in_image=(px>=5 && px<WIDTH+5 && py>=5 && py<HEIGHT+5);
    wire feed=feeding && (!in_image || raw_valid);
    assign raw_ready=ce && feeding && in_image;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin feeding<=0;busy<=0;px<=0;py<=0;canny_f<=0;median_f<=1;low_f<=60;high_f<=130;end
        else begin
            if(start && !busy) begin
                feeding<=1;busy<=1;px<=0;py<=0;canny_f<=canny;
                median_f<=median_enable;low_f<=threshold_low;high_f<=threshold_high;
            end
            if(ce && feed) begin
                if(px==WIDTH+9) begin px<=0;if(py==HEIGHT+9) feeding<=0;else py<=py+1'b1;end
                else px<=px+1'b1;
            end
            if(pixel_valid && pixel_ready && pixel_last) busy<=0;
        end
    end
    wire bv,rv,yv,mwv,mv,gwv,swv,nwv;
    wire [71:0] bt;
    wire [11:0] bx,by,mx,my,gx,gy,sx,sy,nx,ny;
    wire [23:0] rgb;
    wire [7:0] gray;
    wire [215:0] mt;
    wire [287:0] gt,st;
    wire [332:0] nt;
    window3x3 #(WIDTH+10,HEIGHT+10,8) bwin(clk,rst_n,ce,feed,in_image?raw_data:8'd0,bv,bt,bx,by);
    bayer_rgb #(BAYER_PHASE) bayer(clk,rst_n,ce,bv,bt,bx,by,rv,rgb);
    reg [11:0] rgb_x,rgb_y;
    always @(posedge clk) if(ce) begin rgb_x<=bx;rgb_y<=by;end
    v8_rgb_diagnostics #(WIDTH,HEIGHT) diagnostics(
        clk,rst_n,rv && ce,rgb,rgb_x,rgb_y,diag_frame_request,diag_ack,diag_snapshot);
    rgb_to_y8 yconvert(clk,rst_n,ce,rv,rgb,yv,gray);
    wire [23:0] corrected_rgb;
    wire corrected_valid;
    v8_white_balance white_balance(clk,rst_n,ce,rv,rgb,wb_frame,corrected_valid,corrected_rgb);
    reg [11:0] wb_x[0:2],wb_y[0:2];
    integer k;
    always @(posedge clk) if(ce) begin
        wb_x[0]<=rgb_x;wb_y[0]<=rgb_y;
        wb_x[1]<=wb_x[0];wb_y[1]<=wb_y[0];
        wb_x[2]<=wb_x[1];wb_y[2]<=wb_y[1];
    end
    v8_rgb_diagnostics #(WIDTH,HEIGHT) corrected_diagnostics(
        clk,rst_n,corrected_valid && ce,corrected_rgb,wb_x[2],wb_y[2],diag_frame_request,wb_ack,wb_snapshot);
    wire [15:0] corrected565={corrected_rgb[23:19],corrected_rgb[15:10],corrected_rgb[7:3]};
    window3x3 #(WIDTH+8,HEIGHT+8,24) mwin(clk,rst_n,ce,yv,{corrected565,gray},mwv,mt,mx,my);
    wire [71:0] median_taps;
    genvar j;
    generate for(j=0;j<9;j=j+1) begin:mtap
        assign median_taps[j*8+:8]=mt[j*24+:8];
    end endgenerate
    wire [15:0] filtered;
    median9_pipe median(clk,rst_n,ce,mwv,median_taps,median_f,mv,filtered);
    reg [15:0] median_color[0:8];
    always @(posedge clk) if(ce) begin
        median_color[0]<=mt[4*24+8+:16];
        for(k=1;k<9;k=k+1) median_color[k]<=median_color[k-1];
    end
    // 高字节组保留原图，低8位独立携带滤波后的算法灰度。
    window3x3 #(WIDTH+6,HEIGHT+6,32) gwin(clk,rst_n,ce,mv,{median_color[8],filtered},gwv,gt,gx,gy);
    wire [7:0] g[0:8];
    generate for(j=0;j<9;j=j+1) begin:gtap
        assign g[j]=gt[j*32+:8];
    end endgenerate
    reg [9:0] ga,gb,gc;
    reg [23:0] gmeta0,gmeta1;
    reg [7:0] bypass0;
    reg gv0,gv1;
    reg [7:0] smooth;
    wire [11:0] gsum={2'b0,ga}+{1'b0,gb,1'b0}+{2'b0,gc}+12'd8;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin gv0<=0;gv1<=0;end
        else if(ce) begin
            gv0<=gwv;gv1<=gv0;
            ga<={2'b0,g[0]}+{1'b0,g[1],1'b0}+g[2];
            gb<={2'b0,g[3]}+{1'b0,g[4],1'b0}+g[5];
            gc<={2'b0,g[6]}+{1'b0,g[7],1'b0}+g[8];
            gmeta0<=gt[4*32+8+:24];gmeta1<=gmeta0;bypass0<=g[4];
            smooth<=(canny_f || SOBEL_ENHANCE)?gsum[11:4]:bypass0;
        end
    end
    window3x3 #(WIDTH+4,HEIGHT+4,32) swin(clk,rst_n,ce,gv1,{gmeta1,smooth},swv,st,sx,sy);
    wire [7:0] s[0:8];
    generate for(j=0;j<9;j=j+1) begin:stap
        assign s[j]=st[j*32+:8];
    end endgenerate
    reg [9:0] ls,rs,ts,bs,ax,ay;
    reg signed [10:0] dx,dy;
    reg same_sign;
    reg [3:0] gradient_valid;
    reg [23:0] gradient_meta[0:3];
    reg [10:0] magnitude;
    reg [1:0] direction;
    // tan(22.5°)≈106/256，整数比较量化四个梯度方向。
    wire [17:0] ax256={ax,8'b0};
    wire [17:0] ay256={ay,8'b0};
    wire [17:0] ax106=({8'b0,ax}<<6)+({8'b0,ax}<<5)+({8'b0,ax}<<3)+({8'b0,ax}<<1);
    wire [17:0] ay106=({8'b0,ay}<<6)+({8'b0,ay}<<5)+({8'b0,ay}<<3)+({8'b0,ay}<<1);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) gradient_valid<=0;
        else if(ce) begin
            gradient_valid<={gradient_valid[2:0],swv};
            gradient_meta[0]<=st[4*32+8+:24];
            for(k=1;k<4;k=k+1) gradient_meta[k]<=gradient_meta[k-1];
            ls<={2'b0,s[0]}+{1'b0,s[3],1'b0}+s[6];
            rs<={2'b0,s[2]}+{1'b0,s[5],1'b0}+s[8];
            ts<={2'b0,s[0]}+{1'b0,s[1],1'b0}+s[2];
            bs<={2'b0,s[6]}+{1'b0,s[7],1'b0}+s[8];
            dx<=$signed({1'b0,rs})-$signed({1'b0,ls});
            dy<=$signed({1'b0,bs})-$signed({1'b0,ts});
            ax<=dx[10]?-dx:dx;ay<=dy[10]?-dy:dy;same_sign<=dx[10]==dy[10];
            magnitude<={1'b0,ax}+{1'b0,ay};
            if(ay256<=ax106) direction<=0;
            else if(ax256<=ay106) direction<=2;
            else direction<=same_sign?1:3;
        end
    end
    window3x3 #(WIDTH+2,HEIGHT+2,37) nwin(clk,rst_n,ce,gradient_valid[3],
        {gradient_meta[3],direction,magnitude},nwv,nt,nx,ny);
    wire [36:0] center=nt[4*37+:37];
    reg [10:0] n0,n1;
    always @* begin
        case(center[12:11])
            0:begin n0=nt[3*37+:11];n1=nt[5*37+:11];end
            1:begin n0=nt[0*37+:11];n1=nt[8*37+:11];end
            2:begin n0=nt[1*37+:11];n1=nt[7*37+:11];end
            default:begin n0=nt[2*37+:11];n1=nt[6*37+:11];end
        endcase
    end
    wire interior=(canny_f || SOBEL_ENHANCE)?(nx>=5 && nx<WIDTH-5 && ny>=5 && ny<HEIGHT-5):
                          (nx>=3 && nx<WIDTH-3 && ny>=3 && ny<HEIGHT-3);
    // 平台只保留一侧，避免恒定梯度出现双像素宽边缘；弱链由后续迭代完整追踪。
    wire maximum=center[10:0]>n0 && center[10:0]>=n1;
    // Sobel reuses the existing Gaussian/NMS memories. Tangent-side support
    // rejects isolated/incoherent gradient responses without binary morphology
    // that would erase one-pixel contours. Canny keeps its exact old decisions.
    wire sobel_support;
    v8_sobel_support support(nt,high_f,sobel_support);
    wire candidate=interior && ((canny_f || SOBEL_ENHANCE)?maximum:1'b1) &&
                   (canny_f || !SOBEL_ENHANCE || sobel_support);
    assign pixel={6'b0,candidate && center[10:0]>high_f,
                  canny_f && candidate && center[10:0]>low_f,center[36:13]};
    assign pixel_valid=nwv;
    assign pixel_last=nx==WIDTH-1 && ny==HEIGHT-1;
endmodule
