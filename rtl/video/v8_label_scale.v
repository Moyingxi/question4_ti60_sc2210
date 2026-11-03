`timescale 1ns/1ps
// Preserve all four full-resolution component identities in each display cell.
// Only RGB/gray metadata is averaged, exactly as in v8_scale.
module v8_label_scale #(parameter WIDTH=1920,HEIGHT=1080)(
    input clk,rst_n,ce,s_valid,input [37:0] s_data,
    output reg m_valid,output reg [95:0] m_data,output reg m_last
);
    reg [11:0] x,y,xq,yq;
    (* ram_style="block" *) reg [37:0] line[0:WIDTH-1];
    reg [37:0] oldq,dq,oldleft,newleft;
    reg vq;
    wire [9:0] sumy={2'b0,oldleft[7:0]}+oldq[7:0]+newleft[7:0]+dq[7:0]+10'd2;
    wire [6:0] sumr={2'b0,oldleft[23:19]}+oldq[23:19]+newleft[23:19]+dq[23:19]+7'd2;
    wire [7:0] sumg={2'b0,oldleft[18:13]}+oldq[18:13]+newleft[18:13]+dq[18:13]+8'd2;
    wire [6:0] sumb={2'b0,oldleft[12:8]}+oldq[12:8]+newleft[12:8]+dq[12:8]+7'd2;
    always @(posedge clk) if(ce && s_valid) begin oldq<=line[x];line[x]<=s_data;end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin x<=0;y<=0;vq<=0;m_valid<=0;m_last<=0;end
        else if(ce) begin
            vq<=s_valid;m_valid<=0;m_last<=0;
            if(s_valid) begin
                dq<=s_data;xq<=x;yq<=y;
                if(x==WIDTH-1) begin x<=0;y<=(y==HEIGHT-1)?0:y+1'b1;end else x<=x+1'b1;
            end
            if(vq) begin
                oldleft<=oldq;newleft<=dq;
                if(xq[0] && yq[0]) begin
                    m_valid<=1;m_last<=xq==WIDTH-1 && yq==HEIGHT-1;
                    m_data<={16'd0,dq[37:24],newleft[37:24],oldq[37:24],oldleft[37:24],
                              sumr[6:2],sumg[7:2],sumb[6:2],sumy[9:2]};
                end
            end
        end
    end
endmodule
