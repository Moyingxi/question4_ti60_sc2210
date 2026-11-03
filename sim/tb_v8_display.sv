`timescale 1ns/1ps
module tb_v8_display;
    reg clk=0,rst_n=0;always #3.367 clk=~clk;
    wire [9:0] line;wire lv;reg lr=1;reg [151:0] data=0;reg valid=0;wire ready;
    wire [23:0] rgb;wire de,hs,vs;wire [31:0] frames,underruns;
    wire [319:0] shape_status;
    v8_hdmi_display dut(clk,rst_n,line,lv,lr,data,valid,ready,rgb,de,hs,vs,frames,underruns,3'b000,shape_status,12'd0);
    integer fx=0,fy=0,stage=0,srow=0,word_index=0,side=0,j,pcount=0;
    integer qx=0,qy=0,qstage=0,checks=0;reg sending=0;
    reg [4:0] flags;
    reg [31:0] pack_pixel;
    function [4:0] mode_flags(input integer f);
        case(f)
            0:mode_flags=0;1:mode_flags=1;2:mode_flags=2;3:mode_flags=3;
            4:mode_flags=7;5:mode_flags=12;6:mode_flags=15;
            10:mode_flags=6;11:mode_flags=7;default:mode_flags=28;
        endcase
    endfunction
    function [31:0] pixel(input integer x,y,b);
        reg [7:0] gray;reg e;reg [15:0] c;
        begin gray=(x*3+y*5+b*41)&255;e=((x+y)%11)==0;c=b?16'h001f:16'h07e0;
            pixel={c,7'b0,e,gray};end
    endfunction
    function [23:0] expected(input integer x,y,f);
        reg [31:0] v;reg [4:0] m;integer sx,sy,b;
        begin
            expected=0;m=mode_flags(f);sx=x<960?x:x-960;sy=y-270;b=m[3] && x>=960;
            v=pixel(sx,sy,b);
            if(x<1920 && y>=270 && y<810) begin
                if(m[3]) expected=m[4]?{24{v[8]}}:m[0]?(b?24'h0000ff:24'h00ff00):{3{v[7:0]}};
                else if(x>=960) expected={24{v[8]}};
                else if(!m[2] && m[1] && v[8]) expected=24'hff0000;
                else if(m[0]) expected=24'h00ff00;
                else expected={3{v[7:0]}};
                if(f==8 && y>270) expected=0;
                if(f==9) expected=0;
            end
        end
    endfunction
    always @(negedge clk) if(rst_n) begin
        valid=0;
        if(sending) begin
            data={side[0],flags,srow[9:0],word_index[7:0],128'd0};
            for(j=0;j<4;j=j+1) data[j*32+:32]=pixel(word_index*4+j,srow,side);
            valid=1;
        end
        lr=!sending;
    end
    always @(posedge clk) if(rst_n) begin
        // 请求与数据使用公开握手接口，不强制模块内部计数器。
        if(lv && lr) begin sending=1;srow=line;word_index=0;side=0;flags=mode_flags(stage);end
        else if(valid && ready) begin
            if(word_index==239) begin
                word_index=0;
                if(flags[3] && side==0 && (stage<8 || (stage==8 && srow==0))) side=1;
                else sending=0;
            end else word_index=word_index+1;
        end
        #0.001;
        if(checks>1) begin
            if(de!==(qx<1920 && qy<1080) || hs!==(qx>=2008 && qx<2052) || vs!==(qy>=1084 && qy<1089))
                $fatal(1,"1080p60 sync timing x%0d y%0d",qx,qy);
            if(rgb!==expected(qx,qy,qstage)) $fatal(1,"display mode%0d x%0d y%0d got%h expected%h",qstage,qx,qy,rgb,expected(qx,qy,qstage));
        end
        qx=fx;qy=fy;qstage=stage;checks=checks+1;
        if(fx==2199) begin fx=0;if(fy==1124) begin fy=0;stage=stage+1;end else fy=fy+1;end
        else fx=fx+1;
        if(stage==12) begin
            if(underruns!=1079) $fatal(1,"incorrect missing B row count %0d",underruns);
            $display("PASS V8 HDMI live/A-B/replay gray and color, no history overlay, two missing-B frames, 1080p60 timing, no stale B reuse");$finish;
        end
    end
    initial begin repeat(5) @(negedge clk);rst_n=1;end
    initial begin #220000000;$fatal(1,"display timeout");end
endmodule
