`timescale 1ns/1ps
// Display deadline regression: actual 96/148.5 MHz domains, request/data FIFOs,
// frame scheduler and HDMI raster. Committed frames are preloaded fixtures;
// a saturated algorithm reader competes with display. DDR has burst latency,
// beat bubbles and refresh pauses (unlike the old direct line feeder).
module tb_v9_camera_fps_display;
    parameter CHECK=1;
    reg [11:0] camera_bcd=12'h060;
    reg clk=0,pclk=0,rst_n=0;
    always #5.208333 clk=~clk;
    always #3.367003 pclk=~pclk;
    wire [9:0] line_in,line;wire liv,lir,lv,lr;
    wire [151:0] di,do_;wire div,dir,dov,dor;wire [9:0] level;
    wire [23:0] rgb;wire de,hs,vs;wire [31:0] frames,underruns;
    wire wr,rd,ra,rv,rr;wire [31:0] raddr;wire [7:0] rlen;
    reg rdone=0;reg [127:0] rdata=0;
    reg compare=0;reg [1:0] compare_view=0;
    wire [1:0] mode;wire cmp;
    async_fifo #(10,4) requests(pclk,rst_n,line_in,liv,lir,,clk,rst_n,line,lv,lr,);
    async_fifo #(152,9) pixels(clk,rst_n,di,div,dir,level,pclk,rst_n,do_,dov,dor,);
    wire [319:0] shape_status;
    v8_hdmi_display #(.FPS_ENABLE(1),.CAMERA_FPS_ENABLE(1),.FPS_CLK_HZ(2475000)) screen(pclk,rst_n,line_in,liv,lir,do_,dov,dor,rgb,de,hs,vs,frames,underruns,3'b000,shape_status,camera_bcd);
    v8_frame_store store(
        .clk(clk),.rst_n(rst_n),.enable(1'b1),
        .cap_data(146'd0),.cap_valid(1'b0),.cap_level(12'd0),
        .result_data(128'd0),.result_valid(1'b0),.result_level(11'd0),
        .raw_ready(1'b1),.raw_level(11'd0),
        .display_data(di),.display_valid(div),.display_ready(dir),.display_level(level),
        .line_request(line),.line_valid(lv),.line_ready(lr),
        .command_ready(1'b1),.threshold(11'd130),.median_enable(1'b1),
        .wr_req(wr),.wr_accept(1'b0),.wr_ready(1'b0),.wr_done(1'b0),.wr_error(1'b0),
        .rd_req(rd),.rd_addr(raddr),.rd_len(rlen),.rd_accept(ra),
        .rd_data(rdata),.rd_valid(rv),.rd_ready(rr),.rd_done(rdone),.rd_error(1'b0),
        .freeze_press(1'b0),.replay_press(1'b0),.playback_mode(mode),
        .canny_enable(1'b1),.threshold_low(11'd60),.color_enable(1'b0),.overlay_enable(1'b0),
        .compare_view(compare_view),.compare_press(compare),.select_press(1'b0),.prev_press(1'b0),.next_press(1'b0),
        .compare_active(cmp));

    // Test fixture: two complete immutable historical frames and one live frame.
    // Only the producer is replaced; all display scheduling/CDC/control is real.
    reg rb=0,rvalid=0;integer delay_count=0,remaining=0,cycles=0,crossings=0;
    reg [31:0] addr;
    integer request_cycle=0,request_row=0,max_row_cycles=0;
    integer stage=0,fx=0,fy=0,qx=0,qy=0,qstage=0,checks=0,bad_pixels=0;
    reg was_active=0;
    assign ra=rd && !rb && !rdone;
    assign rv=rvalid;
    function [31:0] pix(input integer x,y,side);
        reg [7:0] gray;
        begin gray=40+(x*3+y*5+side*71)%170;pix={16'h07e0,7'd0,((x+y)%13==0),gray};end
    endfunction
    function [127:0] contents(input [31:0] a);
        integer i,offset,x,y,side;reg [31:0] v;
        begin
            contents=0;
            if(a>=32'h02000000 && a<32'h1f000000) begin
                side=(a-32'h02000000)>>21;offset=(a&32'h001fffff)>>2;
                for(i=0;i<4;i=i+1) begin
                    x=(offset+i)%960;y=(offset+i)/960;v=pix(x,y,side);
                    contents[i*32+:32]=v;
                end
            end else if(a>=32'h01000000 && a<32'h01600000) begin
                offset=(a&32'h001fffff)>>2;
                for(i=0;i<4;i=i+1) contents[i*32+:32]=pix((offset+i)%960,(offset+i)/960,0);
            end
        end
    endfunction
    always @(posedge clk) if(rst_n) begin
        cycles<=cycles+1;rdone<=0;
        was_active<=store.row_active;
        if(was_active && !store.row_active) begin
            if(cycles-request_cycle>max_row_cycles) max_row_cycles=cycles-request_cycle;
            if(stage==1 && request_row<6) $display("A/B row %0d scheduled in %0d UI cycles (one line ~1422)",request_row,cycles-request_cycle);
        end
        if(lv && lr) begin request_cycle=cycles;request_row=line;end
        if(ra) begin
            rb<=1;addr<=raddr;remaining<=rlen+1;delay_count<=20;
            if({1'b0,raddr[11:0]}+(rlen+1)*16>4096) begin
                crossings<=crossings+1;
                if(CHECK) $fatal(1,"AXI read crosses 4KiB: %h len %0d",raddr,rlen);
            end
        end
        if(rb && !rvalid) begin
            if(delay_count!=0) delay_count<=delay_count-1;
            // Periodic write-bus occupation plus refresh blocks new read beats.
            else if(cycles%7500>24 && cycles%16>=4) begin rvalid<=1;rdata<=contents(addr);end
        end
        if(rvalid && rr) begin
            rvalid<=0;addr<=addr+16;remaining<=remaining-1;
            if(remaining==1) begin rb<=0;rdone<=1;end
        end
    end
    reg [31:0] value;reg [23:0] expected;
    always @(posedge pclk) if(rst_n) begin
        if(stage==3 && fx==850 && fy==245) camera_bcd<=12'h030;
        #0.001;
        if(checks>1) begin
            expected=0;
            value=pix(qx<960?qx:qx-960,qy-270,(qstage>=1 && qstage<=4) && qx>=960);
            if(qx<1920 && qy>=270 && qy<810) begin
                if(qstage==3 || ((qstage==0 || qstage==5) && qx>=960)) expected={24{value[8]}};
                else if(qstage==2) expected=24'h00ff00;
                else expected={3{value[7:0]}};
            end
            if(de!==(qx<1920 && qy<1080) || hs!==(qx>=2008 && qx<2052) || vs!==(qy>=1084 && qy<1089))
                $fatal(1,"HDMI timing changed");
            if(qx==752 && qy==234) begin
                if(screen.fps_status.visible_bcd!==(qstage<4?12'h060:12'h030))
                    $fatal(1,"wrong atomic FPS text stage%0d %h",qstage,screen.fps_status.visible_bcd);
            end
            if(qx>=752 && qx<944 && qy>=234 && qy<266) begin
                if(rgb!==24'h00ff40 && rgb!==24'h101010) $fatal(1,"FPS OSD color");
            end else if(rgb!==expected) begin
                bad_pixels=bad_pixels+1;
                if(CHECK) $fatal(1,"DDR display stage%0d x%0d y%0d got%h expected%h underruns%0d",qstage,qx,qy,rgb,expected,underruns);
            end
        end
        qx=fx;qy=fy;qstage=stage;checks=checks+1;
        if(fx==2199) begin fx=0;if(fy==1124) begin fy=0;stage=stage+1;end else fy=fy+1;end
        else fx=fx+1;
        if(stage==6) begin
            $display("DDR deadline result underruns=%0d bad_pixels=%0d 4KiB_crossings=%0d max_row_cycles=%0d",underruns,bad_pixels,crossings,max_row_cycles);
            if(CHECK && (underruns!=0 || bad_pixels!=0 || crossings!=0)) $fatal(1,"display regression");
            $display("PASS V9 CAMERA FPS integration: 60fps despite held A/B images, 30fps adopted atomically next raster, six full 1080p rasters and unchanged pixels/timing CHECK=%0d",CHECK);$finish;
        end
    end
    initial begin
        repeat(10) @(negedge clk);rst_n=1;
        @(negedge clk);
        store.result_latest_valid=1;store.result_latest=0;
        store.playback.history_count=2;store.playback.head=0;store.playback.tail=2;
        force store.raw_reading=1'b1;force store.phase=2'd2;
        wait(stage==1);@(negedge clk);compare=1;@(negedge clk);compare=0;
        wait(stage==2);@(negedge clk);compare_view=1;
        wait(stage==3);@(negedge clk);compare_view=2;
        wait(stage==4);@(negedge clk);compare_view=0;
        wait(stage==5);@(negedge clk);compare=1;@(negedge clk);compare=0;
    end
    initial begin #120000000;$fatal(1,"display DDR timeout");end
endmodule
