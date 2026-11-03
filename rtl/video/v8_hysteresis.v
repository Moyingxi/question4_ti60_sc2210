`timescale 1ns/1ps
// 八邻域传播：同一扫描立即利用已经确认的左/上一行强边缘（因果扫描）。
// 仍读取上一轮八邻域；新晋升只沿弱候选传播，不改变完整收敛后的连通集合。
// 调度器使用两个 DDR 帧区反复运行本模块，直到整帧 bit26 均为0。
// 不限制传播轮数；因此可连接任意长、弯曲的弱边缘链，并消除孤立弱链。
module v8_hysteresis #(parameter WIDTH=1920,HEIGHT=1080)(
    input clk,rst_n,start,
    input [31:0] s_data,input s_valid,output s_ready,
    output [31:0] m_data,output m_valid,input m_ready,output m_last,output reg busy
);
    reg feeding;
    reg [11:0] x,y;
    wire ce=!m_valid || m_ready;
    wire in_image=x>=1 && x<=WIDTH && y>=1 && y<=HEIGHT;
    wire feed=feeding && (!in_image || s_valid);
    assign s_ready=ce && feeding && in_image;
    wire [287:0] taps;
    wire [11:0] ox,oy;
    wire window_valid;
    window3x3 #(WIDTH+2,HEIGHT+2,32) win(clk,rst_n,ce,feed,in_image?s_data:32'd0,window_valid,taps,ox,oy);
    wire [31:0] center=taps[4*32+:32];
    wire neighbor=taps[25] | taps[57] | taps[89] | taps[121] |
                  taps[185] | taps[217] | taps[249] | taps[281];
    // 两份单比特行RAM提供独立的N/NE同步读口。NW保留上次读出的旧值，
    // 避免当前行覆盖前一行后误把当前行x-1当成上一行x-1。
    (* ram_style="block" *) reg strong_n[0:WIDTH-1];
    (* ram_style="block" *) reg strong_ne[0:WIDTH-1];
    reg north_q,ne_q,nw_q,left_q;
    reg [31:0] center_q;
    reg neighbor_q,valid_q;
    reg [11:0] x_q,y_q;
    wire causal=(x_q!=0 && left_q) ||
        (y_q!=0 && (north_q || (x_q!=0 && nw_q) || (x_q!=WIDTH-1 && ne_q)));
    wire promote=center_q[24] && !center_q[25] && (neighbor_q || causal);
    wire linked=center_q[25] | promote;
    assign m_valid=valid_q;
    assign m_data={5'b0,promote,linked,center_q[24:0]};
    assign m_last=x_q==WIDTH-1 && y_q==HEIGHT-1;
    always @(posedge clk) begin
        if(ce && window_valid) begin
            north_q<=strong_n[ox];
            ne_q<=strong_ne[ox==WIDTH-1?12'd0:ox+12'd1];
            nw_q<=north_q;
        end
        if(m_valid && m_ready) begin
            strong_n[x_q]<=linked;
            strong_ne[x_q]<=linked;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            feeding<=0;busy<=0;x<=0;y<=0;
            valid_q<=0;center_q<=0;neighbor_q<=0;x_q<=0;y_q<=0;left_q<=0;
        end
        else begin
            if(ce) begin
                valid_q<=window_valid;
                if(window_valid) begin
                    center_q<=center;neighbor_q<=neighbor;x_q<=ox;y_q<=oy;
                end
            end
            if(m_valid && m_ready) left_q<=linked;
            if(start && !busy) begin feeding<=1;busy<=1;x<=0;y<=0;end
            if(ce && feed) begin
                if(x==WIDTH+1) begin x<=0;if(y==HEIGHT+1) feeding<=0;else y<=y+1'b1;end
                else x<=x+1'b1;
            end
            if(m_valid && m_ready && m_last) busy<=0;
        end
    end
endmodule
