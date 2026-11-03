`timescale 1ns/1ps
// ATK common-cathode display. FPGA 1.8V -> on-board TXS0108E -> P4 3.3V.
// seg[0:6]=A..G, seg[7]=DOT; CH1..CH4 are active high.
// All state inputs are synchronous to clk_sys. No image-path backpressure.
module v8_sevenseg_status #(
 parameter MS_CYCLES=96000, POPUP_MS=2000, BLANK_CYCLES=480
)(
 input clk,rst_n,ready,
 input [1:0] playback_mode,
 input compare_active,selected_b,
 input [8:0] index_a,index_b,history_count,replay_remaining,
 input canny_enable,median_enable,color_enable,overlay_enable,select_low,
 input [10:0] threshold_high,threshold_low,
 input [1:0] compare_view,input [2:0] shape_control,
 output reg [7:0] seg_o,output reg [3:0] seg_sel_o,
 output [31:0] shown_ascii
);
 localparam S=0,C=1,L=2,D=3,R=4,O=5,T=6,DETECT=7,AB=8;
 reg [16:0] ms_count;
 wire ms_tick=ms_count==MS_CYCLES-1;
 reg [10:0] popup_left;
 reg [3:0] popup_kind;
 reg [7:0] popup_value;
 reg initialized;
 reg [3:0] mode_q;
 reg [10:0] high_q,low_q;
 reg median_q,color_q,overlay_q,select_q;
 reg [1:0] view_q;
 reg [2:0] shape_q;
 wire [3:0] mode_key={compare_active,playback_mode,canny_enable};
 wire [8:0] ordinal=history_count>=replay_remaining?history_count-replay_remaining:9'd0;
 wire [8:0] compare_ordinal=(selected_b?index_b:index_a)+9'd1;
 reg [7:0] number,prefix;
 reg [31:0] page;
 reg numeric;
 reg [31:0] frame_chars;
 reg [3:0] frame_dots;
 reg [1:0] digit,scan_phase;
 reg [7:0] character;
 assign shown_ascii=frame_chars;
 function [11:0] bcd8(input [7:0] v);
  reg [11:0] b;integer i;
  begin b=0;
   for(i=7;i>=0;i=i-1)begin
    if(b[3:0]>=5)b[3:0]=b[3:0]+3;
    if(b[7:4]>=5)b[7:4]=b[7:4]+3;
    if(b[11:8]>=5)b[11:8]=b[11:8]+3;
    b={b[10:0],v[i]};
   end bcd8=b;
  end
 endfunction
 function [31:0] decimal_page(input [7:0] p,v);
  reg [11:0] b;begin b=bcd8(v);decimal_page={p,4'h3,b[11:8],4'h3,b[7:4],4'h3,b[3:0]};end
 endfunction
 function [6:0] glyph(input [7:0] c);
  begin case(c)
   "0":glyph=7'h3f;"1":glyph=7'h06;"2":glyph=7'h5b;"3":glyph=7'h4f;
   "4":glyph=7'h66;"5":glyph=7'h6d;"6":glyph=7'h7d;"7":glyph=7'h07;
   "8":glyph=7'h7f;"9":glyph=7'h6f;
   "S":glyph=7'h6d;"C":glyph=7'h39;"L":glyph=7'h38;"F":glyph=7'h71;
   "P":glyph=7'h73;"H":glyph=7'h76;"A":glyph=7'h77;"b":glyph=7'h7c;
   "d":glyph=7'h5e;"r":glyph=7'h50;"o":glyph=7'h5c;"t":glyph=7'h78;
   "E":glyph=7'h79;"-":glyph=7'h40;default:glyph=0;
  endcase end
 endfunction
 always @*begin
  page="----";number=0;prefix="S";numeric=0;
  if(ready)begin
   if(popup_left!=0)begin
    number=popup_value;numeric=1;
    case(popup_kind)
     S:prefix="S";C:prefix="C";L:prefix="L";D:prefix="d";
     R:prefix="r";O:prefix="o";T:prefix="t";
     DETECT:begin numeric=0;page={"dEt",4'h3,3'b0,popup_value[0]};end
     AB:begin numeric=0;page={"Ab-",6'b001100,popup_value[1:0]};end
     default:begin numeric=0;page="----";end
    endcase
   end else if(compare_active)begin numeric=1;prefix=selected_b?"b":"A";number=compare_ordinal[7:0];end
   else if(playback_mode==3 || playback_mode==2)begin numeric=1;prefix=playback_mode==3?"H":"P";number=ordinal[7:0];end
   else if(playback_mode==1)page="F---";
   else begin numeric=1;prefix=canny_enable?"C":"S";number=threshold_high[7:0];end
   if(numeric)page=decimal_page(prefix,number);
  end
  case(digit)
   0:character=frame_chars[31:24];1:character=frame_chars[23:16];
   2:character=frame_chars[15:8];default:character=frame_chars[7:0];
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   ms_count<=0;popup_left<=0;popup_kind<=S;popup_value<=0;initialized<=0;mode_q<=0;
   high_q<=0;low_q<=0;median_q<=0;color_q<=0;overlay_q<=0;select_q<=0;view_q<=0;shape_q<=0;
   frame_chars<="----";frame_dots<=0;digit<=3;scan_phase<=3;seg_o<=0;seg_sel_o<=0;
  end else begin
   initialized<=1;mode_q<=mode_key;high_q<=threshold_high;low_q<=threshold_low;
   median_q<=median_enable;color_q<=color_enable;overlay_q<=overlay_enable;select_q<=select_low;
   view_q<=compare_view;shape_q<=shape_control;
   if(ms_tick)begin
    ms_count<=0;seg_sel_o<=0;digit<=digit+1'b1;scan_phase<=0;
    // Latch all digits and dots together at the beginning of a four-digit sweep.
    if(digit==3)begin frame_chars<=page;frame_dots<={median_enable,color_enable,shape_control[0],1'b0};end
   end else begin
    ms_count<=ms_count+1'b1;
    if(scan_phase==0 && ms_count==BLANK_CYCLES)begin seg_o<={frame_dots[3-digit],glyph(character)};scan_phase<=1;end
    else if(scan_phase==1)begin seg_sel_o<=4'b0001<<digit;scan_phase<=2;end
   end
   if(ms_tick && popup_left!=0)popup_left<=popup_left-1'b1;
   if(initialized && ready)begin
    if(threshold_high!=high_q)begin popup_kind<=canny_enable?C:S;popup_value<=threshold_high[7:0];popup_left<=POPUP_MS;end
    if(canny_enable && (threshold_low!=low_q || select_low!=select_q))begin
     popup_kind<=select_low?L:C;popup_value<=select_low?threshold_low[7:0]:threshold_high[7:0];popup_left<=POPUP_MS;
    end
    if(median_enable!=median_q)begin popup_kind<=D;popup_value<={7'd0,median_enable};popup_left<=POPUP_MS;end
    if(color_enable!=color_q)begin popup_kind<=R;popup_value<={7'd0,color_enable};popup_left<=POPUP_MS;end
    if(overlay_enable!=overlay_q)begin popup_kind<=O;popup_value<={7'd0,overlay_enable};popup_left<=POPUP_MS;end
    if(compare_view!=view_q)begin popup_kind<=AB;popup_value<={6'd0,compare_view};popup_left<=POPUP_MS;end
    if(shape_control[2:1]!=shape_q[2:1])begin popup_kind<=T;popup_value<=8'd80+{shape_control[2:1],5'b0};popup_left<=POPUP_MS;end
    if(shape_control[0]!=shape_q[0])begin popup_kind<=DETECT;popup_value<={7'd0,shape_control[0]};popup_left<=POPUP_MS;end
   end
   // Actual mode changes cancel stale popups; no image ready always shows dashes.
   if(!ready || mode_key!=mode_q)popup_left<=0;
  end
 end
endmodule
