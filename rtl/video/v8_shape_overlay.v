`timescale 1ns/1ps
// Six boxes + Chinese names. Coordinates refer to the left 960x540 scene.
module v8_shape_overlay(
    input [11:0] x,input [10:0] y,input enable,valid,overflow,
    input [1:0] threshold_index,input [227:0] boxes,
    output reg hit,output reg [23:0] color
);
    reg [4:0] glyph;reg [3:0] row,col;
    wire font_pixel;
    v8_shape_font font(glyph,row,col,font_pixel);
    reg text_hit;reg [23:0] ink;
    integer i,bx0,bx1,by0,by1,tx,ty,lx,ly,kind,cell_index;
    always @* begin
        hit=0;color=0;glyph=0;row=0;col=0;text_hit=0;ink=24'h00ff40;
        bx0=0;bx1=0;by0=0;by1=0;tx=0;ty=0;lx=0;ly=0;kind=0;cell_index=0;
        if(enable && x<960) begin
            if(y>=234 && y<266 && x>=16 && x<272) begin
                cell_index=(x-16)>>5;row=(y-234)>>1;col=(x-16)>>1;
                if(cell_index<5 || (overflow && cell_index>=6)) begin
                    text_hit=1;ink=overflow?24'hffb000:24'h00ff40;
                    case(cell_index)
                        0:glyph=3;1:glyph=4;
                        2:glyph=threshold_index==0?5:6;
                        3:case(threshold_index) 0:glyph=13;1:glyph=6;2:glyph=9;3:glyph=12;endcase
                        4:case(threshold_index) 0:glyph=5;1:glyph=7;2:glyph=9;3:glyph=11;endcase
                        6:glyph=16;7:glyph=17;
                    endcase
                end
            end
            if(valid && y>=270 && y<810) begin
                for(i=5;i>=0;i=i-1) begin
                    kind=boxes[i*38+36+:2];
                    bx0={boxes[i*38+:9],1'b0};bx1={boxes[i*38+9+:9],1'b1};
                    by0=270+{boxes[i*38+18+:9],1'b0};by1=270+{boxes[i*38+27+:9],1'b1};
                    if(kind!=0 && x>=bx0 && x<=bx1 && y>=by0 && y<=by1 &&
                        (x<bx0+2 || x>bx1-2 || y<by0+2 || y>by1-2)) begin
                        hit=1;color=kind==1?24'h00ff40:kind==2?24'h00cfff:24'hffb030;
                    end
                    tx=kind==3?(bx0>864?864:bx0):(bx0>896?896:bx0);ty=by0>=304?by0-34:by0+2;
                    if(kind!=0 && x>=tx && x<tx+(kind==3?96:64) && y>=ty && y<ty+32) begin
                        lx=x-tx;ly=y-ty;text_hit=1;ink=kind==1?24'h00ff40:kind==2?24'h00cfff:24'hffb030;
                        glyph=kind==3?(lx<32?5'd18:lx<64?5'd19:5'd1):(lx>=32?5'd1:kind==1?5'd0:5'd2);row=ly>>1;col=lx>>1;
                    end
                end
            end
            if(text_hit) begin hit=1;color=font_pixel?ink:24'h101010;end
        end
    end
endmodule
