`timescale 1ns/1ps
module tb_v8_shapes_display;
    reg clk=0,rst_n=0;always #3.367 clk=~clk;
    wire [9:0] line;wire lv;reg lr=1;reg [151:0] data=0;reg valid=0;wire ready;
    wire [23:0] rgb;wire de,hs,vs;wire [31:0] frames,underruns;wire [319:0] shape_status;
    reg [2:0] control=3'b011;
    v8_hdmi_display dut(clk,rst_n,line,lv,lr,data,valid,ready,rgb,de,hs,vs,frames,underruns,control,shape_status,12'd0);
    integer fx=0,fy=0,stage=0,srow=0,word_index=0,side=0,j;
    integer qx=0,qy=0,qstage=0,checks=0,box_checks=0,right_checks=0,text_pixels=0,k,nc,nr,nt;reg sending=0;
    reg [4:0] flags;
    function [31:0] pixel(input integer x,y);
        integer sx,sy,dx,dy;reg dark;
        begin
            sx=x/4;sy=y/4;dx=sx-170;dy=sy-65;
            dark=((sx>=20 && sx<=90 && sy>=30 && sy<=100) && !(sx>=23 && sx<=87 && sy>=33 && sy<=97)) ||
                 (dx*dx+dy*dy<=22*22 && dx*dx+dy*dy>=19*19) ||
                 ((sx-110)*(sx-110)+(sy-15)*(sy-15)<=9*9) ||
                 (sx>=195 && sx<=213 && sy>=6 && sy<=24) ||
                 (sy>=6 && sy<=24 && (sx>145?sx-145:145-sx)<=(sy-6)/2) ||
                 (sy>=108 && sy<=128 && (sx>70?sx-70:70-sx)<=(sy-108)/2);
            pixel={16'hf800,8'd0,dark?8'd20:8'd220};
        end
    endfunction
    always @(negedge clk) if(rst_n) begin
        control=stage==2?3'b010:stage>=3?3'b101:3'b011;
        valid=0;
        if(sending) begin
            data={side[0],flags,srow[9:0],word_index[7:0],128'd0};
            for(j=0;j<4;j=j+1) data[j*32+:32]=pixel(word_index*4+j,srow);
            valid=1;
        end
        lr=!sending;
    end
    always @(posedge clk) if(rst_n) begin
        if(dut.shape_begin)$display("shape begin frame%0d busy=%b valid=%b diag=%h cycles=%0d detected=%h tracked=%h",stage,dut.shape_busy,dut.shape_valid,dut.shape_diagnostics,dut.shape_cycles,dut.detected_boxes,dut.tracked_boxes);
        if(dut.shape_end_pipe[7])$display("shape capture frame%0d input=%0d mask=%0d",stage,dut.shape_edges.input_count,dut.shape_detector.cap_count);
        if(lv && lr) begin sending=1;srow=line;word_index=0;side=0;flags=stage==5?5'd8:stage==4?5'd5:5'd0;end
        else if(valid && ready) begin
            if(word_index==239) begin word_index=0;if(flags[3] && side==0) side=1;else sending=0;end
            else word_index=word_index+1;
        end
        #0.001;
        if(checks>1) begin
            if(de!==(qx<1920 && qy<1080) || hs!==(qx>=2008 && qx<2052) || vs!==(qy>=1084 && qy<1089))
                $fatal(1,"shape overlay changed sync");
            if(qstage<5 && qx>=960 && qx<1920 && qy>=270 && qy<810) begin
                right_checks=right_checks+1;if(rgb!==0) $fatal(1,"shape overlay changed right edge image");
            end
            if((qstage==1 || qstage==4) && qx==80 && qy==440) begin
                if(rgb!==24'h00cfff) begin $display("shape state valid=%b visible=%b busy=%b diag=%h cycles=%0d boxes=%h",dut.shape_valid,dut.visible_valid,dut.shape_busy,dut.shape_diagnostics,dut.shape_cycles,dut.visible_boxes); $fatal(1,"rectangle box stage%0d got%h",qstage,rgb);end
                box_checks=box_checks+1;
            end
            if((qstage==1 || qstage==4) && qx==680 && qy==623) begin
                if(rgb!==24'h00ff40) $fatal(1,"circle box stage%0d got%h",qstage,rgb);
                box_checks=box_checks+1;
            end
            if(qstage==1 && qx>=80 && qx<144 && qy>=356 && qy<388 && rgb==24'h00cfff) text_pixels=text_pixels+1;
            if(qstage==1 && qx==0 && qy==900)begin
                nc=0;nr=0;nt=0;
                for(k=0;k<6;k=k+1)case(shape_status[k*38+36+:2])1:nc=nc+1;2:nr=nr+1;3:nt=nt+1;endcase
                if(nc!=2 || nr!=2 || nt!=2)$fatal(1,"six-target display snapshot circle=%0d rectangle=%0d triangle=%0d",nc,nr,nt);
            end
            if((qstage==2 || qstage==3 || qstage==5) && qx==80 && qy==440 && rgb!==24'h141414)
                $fatal(1,"disabled/changed threshold/AB reused annotation stage%0d %h",qstage,rgb);
            if(qstage==4 && qx==400 && qy==500 && rgb!==24'hff0000) $fatal(1,"color replay changed");
        end
        qx=fx;qy=fy;qstage=stage;checks=checks+1;
        if(fx==2199) begin fx=0;if(fy==1124) begin fy=0;stage=stage+1;end else fy=fy+1;end else fx=fx+1;
        if(stage==6) begin
            if(underruns!=0 || box_checks!=4 || text_pixels<100 || right_checks<1000000)
                $fatal(1,"incomplete checks underrun%0d boxes%0d text%0d",underruns,box_checks,text_pixels);
            $display("PASS full 1080p shape display: sampled gray -> classification -> Chinese glyphs/boxes, on/off, threshold change, color replay, AB suppression, unchanged right image/timing");$finish;
        end
    end
    initial begin repeat(5) @(negedge clk);rst_n=1;end
    initial begin #120000000;$fatal(1,"shape display timeout");end
endmodule
