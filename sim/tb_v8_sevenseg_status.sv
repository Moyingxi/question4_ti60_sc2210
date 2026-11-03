`timescale 1ns/1ps
module tb_v8_sevenseg_status;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,ready=0,integrated=0;
 reg [1:0] pm=0,cv=0;reg ca=0,sb=0,ce=0,me=1,co=0,ov=0,sl=0;
 reg [8:0] ia=0,ib=0,hc=232,rr=231;reg [10:0] hi=20,lo=0;reg [2:0] sc=3;
 reg [15:0] pressed=0;wire [10:0] real_hi,real_lo;
 wire real_me,real_ce,real_co,real_ov,real_sl;wire [1:0] real_cv;wire [2:0] real_sc;wire [31:0] telemetry;
 v8_controls #(2) controls(clk,rst_n,1'b1,1'b1,pressed,real_hi,real_lo,real_me,real_ce,real_co,real_ov,real_cv,real_sl,real_sc,telemetry);
 reg fs=0,fp=0,rp=0,cp=0,sp=0,prev=0,next=0,rs=0,rf=0;
 wire rec,record_busy;wire [8:0] slot,history,remaining,viewa,viewb,pia,pib;
 wire [1:0] mode;wire vh,hold_live,compare,waiting,selected;
 v8_playback_control playback(clk,rst_n,fp,rp,cp,sp,prev,next,fs,1'b1,rs,rf,1'b1,
  rec,slot,record_busy,history,mode,vh,hold_live,compare,viewa,viewb,remaining,waiting,selected,pia,pib);
 wire [7:0] seg;wire [3:0] sel,logical_sel;wire [31:0] shown;
 assign sel={logical_sel[0],logical_sel[1],logical_sel[2],logical_sel[3]};
 v8_sevenseg_status #(8,20,1) dut(clk,rst_n,ready,
  integrated?mode:pm,integrated?compare:ca,integrated?selected:sb,
  integrated?pia:ia,integrated?pib:ib,integrated?history:hc,integrated?remaining:rr,
  integrated?real_ce:ce,integrated?real_me:me,integrated?real_co:co,integrated?real_ov:ov,integrated?real_sl:sl,
  integrated?real_hi:hi,integrated?real_lo:lo,integrated?real_cv:cv,integrated?real_sc:sc,seg,logical_sel,shown);
 // Exercise the actual 96MHz/1ms/480-clock default, not only shortened parameters.
 wire [7:0] default_seg;wire [3:0] default_sel;wire [31:0] default_shown;
 v8_sevenseg_status default_timing(clk,rst_n,ready,pm,ca,sb,ia,ib,hc,rr,
  ce,me,co,ov,sl,hi,lo,cv,sc,default_seg,default_sel,default_shown);
 integer dc=0,blank_at=0;reg [3:0] default_old=0,default_seen=0;
 always @(negedge clk)if(rst_n)begin
  dc=dc+1;
  if(default_sel==0 && default_old!=0)blank_at=dc;
  if(default_sel!=0 && default_old==0)begin
   if(dc-blank_at<480)$fatal(1,"default scan lacks5us blanking");
   default_seen=default_seen|default_sel;
  end
  default_old=default_sel;
 end
 reg [7:0] old_seg=0;reg [3:0] old_sel=0;reg [31:0] old_shown=0;
 integer enabled=0,n;reg [31:0] expected;
 always @(negedge clk)if(rst_n)begin
  if(sel!=0 && (sel&(sel-1))!=0)$fatal(1,"multiple digits enabled");
  if(seg!=old_seg && sel!=0)$fatal(1,"segments changed while digit enabled");
  if(old_sel!=0 && sel!=0 && old_sel!=sel)$fatal(1,"digit change lacks blanking");
  if(shown!=old_shown && sel!=0)$fatal(1,"frame text torn during active scan");
  if(sel!=0)enabled=enabled+1;
  old_seg=seg;old_sel=sel;old_shown=shown;
 end
 task expect_page(input [31:0] value);begin
  repeat(40)@(negedge clk);
  if(shown!==value)$fatal(1,"display got %s expected %s",shown,value);
 end endtask
 task key(input integer k);begin @(negedge clk);pressed=16'b1<<k;@(negedge clk);pressed=0;end endtask
 task event_boundary(input integer which);begin
  @(negedge clk);fs=1;rp=which==1;fp=which==2;cp=which==3;
  @(negedge clk);fs=0;rp=0;fp=0;cp=0;
 end endtask
 task boundary;begin @(negedge clk);fs=1;@(negedge clk);fs=0;end endtask
 initial begin
  repeat(3)@(negedge clk);if(sel!==0 || seg!==0)$fatal(1,"unsafe reset outputs");rst_n=1;
  expect_page("----");ready=1;expect_page("S020");
  // Independent physical segment check, known literal S020 and configured dots.
  repeat(64)begin @(negedge clk);case(sel)
   8:if(seg!==8'hed)$fatal(1,"physical left CH4 S/dot wrong");
   4:if(seg!==8'h3f)$fatal(1,"physical second CH3 zero wrong");
   2:if(seg!==8'hdb)$fatal(1,"physical third CH2 two/dot wrong");
   1:if(seg!==8'h3f)$fatal(1,"physical right CH1 zero wrong");
  endcase end
  for(n=0;n<=250;n=n+1)begin
   hi=n;expected[31:24]="S";expected[23:16]=48+n/100;
   expected[15:8]=48+(n/10)%10;expected[7:0]=48+n%10;expect_page(expected);
  end
  ce=1;hi=20;expect_page("C020");sl=1;expect_page("L000");lo=15;expect_page("L015");
  repeat(200)@(negedge clk);expect_page("C020");
  pm=1;expect_page("F---");me=0;expect_page("d000");repeat(200)@(negedge clk);expect_page("F---");
  co=1;expect_page("r001");ov=1;expect_page("o001");sc=2;expect_page("dEt0");sc=6;expect_page("t176");
  cv=2;expect_page("Ab-2");pm=2;expect_page("P001");rr=0;expect_page("P232");pm=3;expect_page("H232");
  ca=1;ia=0;ib=231;expect_page("A001");sb=1;expect_page("b232");
  ready=0;expect_page("----");ready=1;expect_page("b232");
  // Real playback/controller interaction: 3 committed frames, pause, compare.
  integrated=1;expect_page("S020");
  for(n=0;n<3;n=n+1)begin @(negedge clk);rs=1;@(negedge clk);rs=0;rf=1;@(negedge clk);rf=0;end
  event_boundary(1);expect_page("P001");boundary();expect_page("P002");
  event_boundary(2);expect_page("H002");
  event_boundary(3);expect_page("A001");sp=1;@(negedge clk);sp=0;expect_page("b003");
  key(15);expect_page("t144");key(14);expect_page("dEt0");
  event_boundary(3);expect_page("S020");
  key(7);expect_page("C020");key(6);expect_page("L000");key(5);expect_page("L005");
  if(enabled<100)$fatal(1,"scan never enabled");
  repeat(500000)@(negedge clk);
  if(default_seen!=15)$fatal(1,"default scan failed to visit all four digits");
  rst_n=0;#1;if(sel!==0 || seg!==0)$fatal(1,"reset did not immediately blank");
  $display("PASS sevenseg: all thresholds0..250, physical segment/dot order, blank-before-change, atomic sweeps, mode priority, popups, real controls/playback ordinal and232 boundary");$finish;
 end
endmodule
