`timescale 1ns/1ps
// Passive RGB888 statistics before gray conversion / RGB565 quantization.
// Bayer output has four padding pixels around the original image.
// Toggle request; capture the NEXT complete frame, then hold all words until
// another request. No asynchronous multi-bit snapshot crosses clock domains.
module v8_rgb_diagnostics #(parameter WIDTH=1920, HEIGHT=1080)(
    input clk,rst_n,valid,input [23:0] rgb,input [11:0] x,y,
    input request,output reg ack,output reg [319:0] snapshot
);
    reg token,armed;
    reg [31:0] total,usable,sr,sg,sb,dark,saturated,snapshot_seq;
    reg [7:0] minr,ming,minb,maxr,maxg,maxb;
    wire [7:0] r=rgb[23:16],g=rgb[15:8],b=rgb[7:0];
    wire roi=x>=WIDTH/4+4 && x<3*WIDTH/4+4 &&
             y>=HEIGHT/4+4 && y<3*HEIGHT/4+4;
    wire low=(r<=4 || g<=4 || b<=4);
    wire high=(r>=250 || g>=250 || b>=250);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ack<=0;token<=0;armed<=0;snapshot<=0;snapshot_seq<=0;
            total<=0;usable<=0;sr<=0;sg<=0;sb<=0;dark<=0;saturated<=0;
            minr<=255;ming<=255;minb<=255;maxr<=0;maxg<=0;maxb<=0;
        end else if(valid) begin
            if(x==0 && y==0) begin
                token<=request;armed<=request!=ack;
                total<=0;usable<=0;sr<=0;sg<=0;sb<=0;dark<=0;saturated<=0;
                minr<=255;ming<=255;minb<=255;maxr<=0;maxg<=0;maxb<=0;
            end
            if(roi) begin
                total<=total+1'b1;
                if(r<minr) minr<=r;if(g<ming) ming<=g;if(b<minb) minb<=b;
                if(r>maxr) maxr<=r;if(g>maxg) maxg<=g;if(b>maxb) maxb<=b;
                if(low) dark<=dark+1'b1;
                if(high) saturated<=saturated+1'b1;
                if(!low && !high) begin
                    usable<=usable+1'b1;sr<=sr+r;sg<=sg+g;sb<=sb+b;
                end
            end
            if(x==WIDTH+7 && y==HEIGHT+7 && armed) begin
                snapshot_seq<=snapshot_seq+1'b1;ack<=token;armed<=0;
                snapshot<={saturated,dark,{8'b0,maxr,maxg,maxb},{8'b0,minr,ming,minb},
                           sb,sg,sr,usable,total,snapshot_seq+32'd1};
            end
        end
    end
endmodule
