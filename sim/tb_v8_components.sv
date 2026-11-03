`timescale 1ns/1ps
module tb_v8_components;
    parameter W=64,H=48,LB=12,FIRST=0,LAST=20;
    localparam N=W*H;
    reg clk=0;always #3.367 clk=~clk;
    reg rst_n=0,start=0,sv=0,mr=0;
    reg [31:0] sd=0;
    wire sr,mv,ml,busy,done,overflow;
    wire [LB+23:0] md;
    wire [LB:0] used;
    reg [4*LB-1:0] query=0;wire [3:0] marks;
    v8_components #(W,H,LB) dut(clk,rst_n,start,sd,sv,sr,md,mv,mr,ml,busy,done,overflow,used,query,marks,1'b1);
    reg weak_map[0:N-1],strong_map[0:N-1],truth[0:N-1];
    reg [LB-1:0] label_image[0:N-1];
    integer queue[0:N-1];integer head,tail,k,j,x,y,xx,yy,dy,dx,frame,sent,received,cycles,total_cycles;
    integer rng=32'h7654abcd;integer random_word;
    reg took;
    function [23:0] meta(input integer idx);meta=(idx*1343+frame*777)&24'hffffff;endfunction
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        for(frame=FIRST;frame<LAST;frame=frame+1) begin
            head=0;tail=0;
            for(k=0;k<N;k=k+1) begin
                x=k%W;y=k/W;random_word=$random(rng);
                weak_map[k]=(random_word & 255)<(frame%7+1)*32;
                strong_map[k]=((random_word>>8)&255)<8;
                if(frame==0) begin weak_map[k]=0;strong_map[k]=0;end
                if(frame==1) begin weak_map[k]=1;strong_map[k]=k==N-1;end
                if(frame==2) begin weak_map[k]=(x+y)%2==0;strong_map[k]=k==0;end
                if(frame==3) begin weak_map[k]=x%2==0 && y%2==0;strong_map[k]=k==0;end
                if(frame==4) begin weak_map[k]=x==y || x==W-1-y;strong_map[k]=k==0;end
                if(frame==5) begin
                    weak_map[k]=(y>=2 && y<H-2 && y%4==2 && x>=2 && x<W-2) ||
                        (y>=2 && y<H-6 && (((y-2)/4)%2==0?x==W-3:x==2));
                    strong_map[k]=(x==2 && y==2);
                end
                truth[k]=strong_map[k];
                if(strong_map[k]) begin queue[tail]=k;tail=tail+1;end
            end
            while(head<tail) begin
                k=queue[head];head=head+1;x=k%W;y=k/W;
                for(dy=-1;dy<=1;dy=dy+1) for(dx=-1;dx<=1;dx=dx+1) begin
                    xx=x+dx;yy=y+dy;j=yy*W+xx;
                    if(xx>=0 && xx<W && yy>=0 && yy<H)
                        if((weak_map[j] || strong_map[j]) && !truth[j]) begin truth[j]=1;queue[tail]=j;tail=tail+1;end
                end
            end
            @(negedge clk);start=1;@(negedge clk);start=0;
            sent=0;received=0;cycles=0;sv=0;mr=0;took=0;
            while(busy || received<N) begin
                if(!sv || took) begin
                    sv=sent<N && cycles%7!=2;
                    if(sv) sd={6'd0,strong_map[sent],weak_map[sent],meta(sent)};
                end
                mr=cycles%11!=5;
                @(posedge clk);
                took=sv && sr;
                if(took) sent=sent+1;
                if(mv && mr) begin
                    if(md[23:0]!==meta(received)) $fatal(1,"metadata index=%0d",received);
                    if(ml!==(received==N-1)) $fatal(1,"last index=%0d",received);
                    label_image[received]=md[24+:LB];received=received+1;
                end
                @(negedge clk);cycles=cycles+1;
                if(cycles>200*N) $fatal(1,"timeout state=%0d",dut.state);
            end
            sv=0;mr=1;
            if(overflow) begin
                if(LB>=12) $fatal(1,"unexpected label overflow");
                $display("overflow frame=%0d labels=%0d cycles=%0d",frame,used,cycles);
            end else begin
                for(k=0;k<N;k=k+1) begin
                    query={4{label_image[k]}};
                    @(negedge clk);
                    if(marks!=={4{truth[k]}}) $fatal(1,"BFS mismatch frame=%0d pixel=%0d label=%0d got=%b expected=%b",frame,k,label_image[k],marks,truth[k]);
                end
            end
            $display("frame=%0d labels=%0d overflow=%b cycles=%0d",frame,used,overflow,cycles);
        end
        $display("PASS components 20 frames independent BFS, stalls, metadata, restart, overflow LB=%0d",LB);$finish;
    end
endmodule
