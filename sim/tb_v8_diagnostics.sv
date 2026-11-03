`timescale 1ns/1ps
module tb_v8_diagnostics;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,valid=0,request=0;
    reg [23:0] rgb=0;
    reg [11:0] x=0,y=0;
    wire ack;wire [319:0] snapshot;
    v8_rgb_diagnostics #(16,12) stats(clk,rst_n,valid,rgb,x,y,request,ack,snapshot);
    reg [1:0] mode=0;reg de=0,hs=0,vs=0;
    wire [23:0] out;wire ode,ohs,ovs;wire [1:0] active;
    v8_diagnostic_display #(32) display(clk,rst_n,mode,rgb,de,hs,vs,out,ode,ohs,ovs,active);
    integer xx,yy,k;reg [319:0] held;reg [23:0] expected;
    task frame(input bit mid_request);
        begin
            for(yy=0;yy<20;yy=yy+1) for(xx=0;xx<24;xx=xx+1) begin
                @(negedge clk);valid=0;
                repeat((xx+yy)%3) @(negedge clk);
                valid=1;x=xx;y=yy;rgb=24'h326496;
                if(xx==8 && yy==7) rgb=24'h006496;
                if(xx==9 && yy==7) rgb=24'hff6496;
                if(mid_request && xx==12 && yy==10) request=~request;
            end
            @(negedge clk);valid=0;
        end
    endtask
    task check_stats(input integer seq);
        begin
            if(snapshot[31:0]!==seq || snapshot[63:32]!==48 || snapshot[95:64]!==46 ||
               snapshot[127:96]!==2300 || snapshot[159:128]!==4600 || snapshot[191:160]!==6900 ||
               snapshot[223:192]!==32'h00006496 || snapshot[255:224]!==32'h00ff6496 ||
               snapshot[287:256]!==1 || snapshot[319:288]!==1)
                $fatal(1,"snapshot mismatch %h",snapshot);
        end
    endtask
    task pulse_vs;
        begin @(negedge clk);vs=1;@(negedge clk);vs=0;end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        frame(0);if(snapshot!==0 || ack!==0) $fatal(1,"unrequested snapshot");
        frame(1);if(snapshot!==0 || ack!==0) $fatal(1,"partial frame accepted");
        frame(0);if(ack!==1) $fatal(1,"no ack");check_stats(1);held=snapshot;
        frame(0);if(snapshot!==held) $fatal(1,"snapshot not held");
        request=0;frame(0);check_stats(2);if(ack!==0) $fatal(1,"second ack");
        // Inactive mode: RGB and every timing signal are delayed by one cycle.
        @(negedge clk);de=1;hs=1;rgb=24'h123456;
        @(posedge clk);#1;if(out!==24'h123456 || !ode || !ohs || ovs) $fatal(1,"bypass alignment");
        @(negedge clk);de=0;hs=0;mode=1;
        repeat(4) @(negedge clk);
        if(active!==0) $fatal(1,"mode changed outside frame boundary");
        pulse_vs();if(active!==1) $fatal(1,"mode not latched");
        for(k=0;k<32;k=k+1) begin
            @(negedge clk);de=1;
            case(k/4)
              0:expected=24'hffffff;1:expected=24'hffff00;2:expected=24'h00ffff;3:expected=24'h00ff00;
              4:expected=24'hff00ff;5:expected=24'hff0000;6:expected=24'h0000ff;7:expected=0;
            endcase
            @(posedge clk);#1;if(out!==expected || !ode) $fatal(1,"bar x=%0d got=%h expected=%h",k,out,expected);
        end
        @(negedge clk);de=0;mode=2;
        @(posedge clk);#1;if(out!==0 || ode) $fatal(1,"blanking");
        pulse_vs();
        for(k=0;k<32;k=k+1) begin
            @(negedge clk);de=1;expected={3{8'((k/2)*17)}};
            @(posedge clk);#1;if(out!==expected) $fatal(1,"gray x=%0d",k);
        end
        @(negedge clk);de=0;mode=0;pulse_vs();
        @(negedge clk);de=1;rgb=24'habcdef;
        @(posedge clk);#1;if(out!==24'habcdef) $fatal(1,"restore bypass");
        $display("PASS V8 diagnostics complete-frame ROI, stalls, held snapshots, clipping, RGB bars, gray steps, frame switch and bypass timing");
        $finish;
    end
    initial begin #200000;$fatal(1,"timeout");end
endmodule
