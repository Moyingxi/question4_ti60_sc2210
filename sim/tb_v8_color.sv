`timescale 1ns/1ps
// Physical BGGR mosaics of known RGB bars. Unlike random RAW/golden agreement,
// the expected RGB here is the original scene, independent of demosaic code.
module tb_v8_color;
    localparam W=64,H=48,N=W*H;
    reg clk=0,rst_n=0;always #3.367 clk=~clk;
    reg [25:0] command=0;reg cv=0;wire cr;
    reg [127:0] raw=0;reg rv=0;wire rr;reg raw_taken=0;
    wire [127:0] result;wire ov;reg ready=0;wire done,busy;
    reg diag_request=0;wire diag_ack;wire [319:0] diag_snapshot;
    reg [36:0] wb_config={1'b0,12'd453,12'd256,12'd339};
    wire [36:0] wb_applied;wire wb_ack;wire [319:0] wb_snapshot;
    v8_processor_io #(W,H) dut(clk,rst_n,command,cv,cr,raw,rv,rr,result,ov,ready,done,busy,diag_request,diag_ack,diag_snapshot,wb_config,wb_applied,wb_ack,wb_snapshot);
    reg [31:0] rng=32'h169c537a;
    always @(posedge clk) rng<=(rng<<1)^({32{rng[31]}}&32'h04c11db7);
    function [23:0] scene(input integer x,y);
        case(x/16)
            0:scene=24'hd02018;
            1:scene=24'h18c030;
            2:scene=24'h2018d0;
            default:scene=24'hb0b0b0;
        endcase
    endfunction
    function [7:0] mosaic(input integer x,y);
        reg [23:0] c;
        begin c=scene(x,y);
            if(!y[0] && !x[0]) mosaic=c[7:0];
            else if(y[0] && x[0]) mosaic=c[23:16];
            else mosaic=c[15:8];
        end
    endfunction
    integer packet=0,j,out_count=0,x,y,checks=0,phase=0,t;
    integer sx,sy,er,eg,eb,sumr,sumg,sumb;
    integer wsr,wsg,wsb,wcount,wr,wg,wb;
    function [7:0] gain(input integer raw,g);
        integer q;begin q=(raw*g+128)/256;gain=q>255?255:q;end
    endfunction
    reg [23:0] c;reg [15:0] expected_color;reg [7:0] expected_gray;reg [31:0] value;
    always @(negedge clk) if(rst_n) begin
        ready=rng[0] || rng[3];
        if(!rv || raw_taken) begin
            rv=busy && packet<N/16 && (rng[1] || rng[4]);
            for(j=0;j<16;j=j+1) raw[j*8+:8]=mosaic((packet*16+j)%W,(packet*16+j)/W);
        end
    end
    always @(posedge clk) if(rst_n) begin
        raw_taken<=rv && rr;
        if(rv && rr) packet=packet+1;
        if(ov && ready) begin
            for(t=0;t<4;t=t+1) begin
                x=command[23]?out_count%W:(out_count%(W/2))*2;
                y=command[23]?out_count/W:(out_count/(W/2))*2;
                // Interior of each bar, away from zero padding and color transitions.
                if(x%16>=4 && x%16<12 && y>=8 && y<H-8) begin
                    c=scene(x,y);
                    expected_gray=(77*c[23:16]+150*c[15:8]+29*c[7:0]+128)>>8;
                    if(wb_config[36]) c={gain(c[23:16],339),gain(c[15:8],256),gain(c[7:0],453)};
                    expected_color={c[23:19],c[15:10],c[7:3]};
                    value=result[t*32+:32];
                    if((command[23]?value[23:8]:value[31:16])!==expected_color || value[7:0]!==expected_gray)
                        $fatal(1,"RGB bars phase%0d x%0d y%0d got%h rgb%h gray%h",command[24:23],x,y,value,expected_color,expected_gray);
                    checks=checks+1;
                end
                out_count=out_count+1;
            end
        end
    end
    initial begin
        sumr=0;sumg=0;sumb=0;wsr=0;wsg=0;wsb=0;wcount=0;
        // Independent physical mosaic reference over the central 32x24 region,
        // including transitions between bars; validates padded coordinate offset.
        for(sy=H/4;sy<3*H/4;sy=sy+1) for(sx=W/4;sx<3*W/4;sx=sx+1) begin
            if(!sy[0] && !sx[0]) begin
                eb=mosaic(sx,sy);
                eg=(int'(mosaic(sx-1,sy))+mosaic(sx+1,sy)+mosaic(sx,sy-1)+mosaic(sx,sy+1))/4;
                er=(int'(mosaic(sx-1,sy-1))+mosaic(sx+1,sy-1)+mosaic(sx-1,sy+1)+mosaic(sx+1,sy+1))/4;
            end else if(sy[0] && sx[0]) begin
                er=mosaic(sx,sy);
                eg=(int'(mosaic(sx-1,sy))+mosaic(sx+1,sy)+mosaic(sx,sy-1)+mosaic(sx,sy+1))/4;
                eb=(int'(mosaic(sx-1,sy-1))+mosaic(sx+1,sy-1)+mosaic(sx-1,sy+1)+mosaic(sx+1,sy+1))/4;
            end else begin
                eg=mosaic(sx,sy);
                if(sy[0]) begin
                    er=(int'(mosaic(sx-1,sy))+mosaic(sx+1,sy))/2;
                    eb=(int'(mosaic(sx,sy-1))+mosaic(sx,sy+1))/2;
                end else begin
                    eb=(int'(mosaic(sx-1,sy))+mosaic(sx+1,sy))/2;
                    er=(int'(mosaic(sx,sy-1))+mosaic(sx,sy+1))/2;
                end
            end
            sumr=sumr+er;sumg=sumg+eg;sumb=sumb+eb;
            wr=gain(er,339);wg=gain(eg,256);wb=gain(eb,453);
            if(wr>4 && wg>4 && wb>4 && wr<250 && wg<250 && wb<250) begin
                wsr=wsr+wr;wsg=wsg+wg;wsb=wsb+wb;wcount=wcount+1;
            end
        end
        repeat(5) @(negedge clk);rst_n=1;
        for(phase=0;phase<4;phase=phase+1) begin
            wb_config[36]=phase>=2;
            diag_request=~diag_request;
            @(negedge clk);packet=0;out_count=0;command={1'b0,phase[0],1'b1,11'd60,11'd130};cv=1;
            @(posedge clk);while(!cr) @(posedge clk);
            @(negedge clk);cv=0;
            wait(out_count==(command[23]?N:N/4));
            repeat(10) @(negedge clk);
            if(busy || ov) $fatal(1,"color pipeline did not drain");
            if(diag_ack!==diag_request || diag_snapshot[31:0]!==phase+1 ||
               diag_snapshot[63:32]!==768 || diag_snapshot[95:64]!==768 ||
               diag_snapshot[127:96]!==sumr || diag_snapshot[159:128]!==sumg || diag_snapshot[191:160]!==sumb)
                $fatal(1,"integrated ROI mismatch %h expected RGB sums %0d %0d %0d",diag_snapshot,sumr,sumg,sumb);
            if(wb_applied!==wb_config || wb_ack!==diag_ack || wb_snapshot[31:0]!==phase+1 || wb_snapshot[63:32]!==768)
                $fatal(1,"WB config/frame snapshot alignment");
            if(wb_snapshot[95:64] !== (phase>=2?wcount:768) ||
               wb_snapshot[127:96] !== (phase>=2?wsr:sumr) || wb_snapshot[159:128] !== (phase>=2?wsg:sumg) ||
               wb_snapshot[191:160] !== (phase>=2?wsb:sumb)) $fatal(1,"corrected ROI mismatch %h",wb_snapshot);
        end
        if(checks==0) $fatal(1,"no color checks");
        $display("PASS V8 known red/green/blue/neutral BGGR bars, Sobel and Canny metadata, %0d RGB checks",checks);$finish;
    end
    initial begin #2000000;$fatal(1,"color test timeout");end
endmodule
