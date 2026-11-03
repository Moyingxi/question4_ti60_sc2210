"""Generate the V8 cached, packed-RAM support-contour detector."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
(root/'rtl/video/v8_shape_detector.v').write_text(r'''`timescale 1ns/1ps
// Exact 8-connected contours, 16 support directions, polygon edge verification.
// Packed 20-bit statistics RAM plus a write-back component cache avoids wide
// shallow RAMs. Type 1=circle, 2=rectangle (rotated included), 3=triangle.
module v8_shape_detector #(parameter W=480,H=270)(
 input clk,rst_n,frame_start,frame_end,sample_valid,sample_dark,
 output reg [227:0] boxes,output reg result_valid,overflow,busy,
 output reg [31:0] completed,output reg [21:0] elapsed_cycles,output [9:0] diagnostics
);
 localparam IDLE=0,INIT=1,READ=2,GET=3,N2=4,N3=5,FS=6,FIND=7,NEXT=8,
  ALLOC=9,MR=10,UPDATE=11,BG=12,ADV=13,LOAD=14,CACHE_GOT=15,
  RD_ADDR=16,RD_DATA=17,MW=18,MERGE=19,MFIND=20,CHILD_REQ=21,
  CHILD_GOT=22,ROOT_REQ=23,ROOT_GOT=24,MERGE_NEXT=25,
  CLASS_REQ=26,CLASS_GEOM=27,POINT=28,ACC=29,CLOSE=30,KIND=31,
  POLY_VEC=32,POLY_CHECK=33,P_PREP=34,P_CENTER=35,P_ADDR=36,
  P_WAIT=37,P_READ=38,P_NEXT=39,INSERT=40,CLASS_NEXT=41,FINISH=42,
  SIMPLIFY_VEC=43,SIMPLIFY_CHECK=44,SIMPLIFY_REMOVE=45,
  POLY_MUL=46,SIMPLIFY_MUL=47,RAD_MUL=48,RAD_SUM=49,APO_SCALE=50,
  NOISE_CHECK=51,NOISE_ADDR=52,NOISE_WAIT=53,NOISE_READ=54,
  MASK_WAIT0=55,MASK_WAIT1=56,PROBE_WAIT0=57,PROBE_WAIT1=58,NOISE_WAIT0=59,NOISE_WAIT1=60,FIND_WAIT=61,MFIND_WAIT=62;
 reg [1:0] noise_index,error_reason;
 reg [5:0] state,mem_return;
 reg [17:0] cap_count,pixel_index;
 reg [8:0] px,py;
 reg [7:0] parent[0:255],neighbors[0:3];
 reg [7:0] next_label,left_label,root_work,find_label,chosen,scan_label;
 assign diagnostics={error_reason,(next_label==0?8'd255:next_label-8'd1)};
 reg [1:0] ni;
 reg [7:0] parent_q;

 (* ram_style="block" *) reg [7:0] rows[0:1023];

 reg [7:0] row_q;wire [19:0] stats_q;
 reg [9:0] mask_pack;wire [9:0] mask_word_q;
 reg [3:0] mask_pack_bit,mask_bit_address_q,mask_bit_q;
 reg [13:0] mask_pack_address,mask_word_address_q;
 reg [34:0] mask_div_product_q;
 reg [16:0] mask_address_q;
 wire mask_q=mask_word_q[mask_bit_q];
 reg [11:0] init_address;
 reg [7:0] mem_label,cache_label;
 reg [3:0] mem_word;
 reg [319:0] mem_shift,stat_value,cache_value,child;
 reg cache_valid;
 reg [227:0] pending_boxes;
 reg [17:0] scores[0:5];
 reg [8:0] bw,bh,tolerance;
 reg [8:0] xmin,xmax,ymin,ymax;
 reg [17:0] box_area;
 reg [17:0] corners[0:15],point_q,previous_support;
 reg [8:0] max_support_step;
 reg [4:0] point_index,corner_count,edge_index,simplify_index;
 reg signed [11:0] dx2,dy2;
 reg [21:0] min_r2,max_r2;
 reg signed [12:0] apothem_dot;
 reg [25:0] apothem_square;
 reg [29:0] apothem_scaled,min_apothem,max_apothem;
 reg [1:0] candidate_kind,probe_fraction;
 reg [17:0] edge_a,edge_b;
 reg [8:0] probe_x,probe_y;
 reg [16:0] probe_address;
 reg [4:0] neighbor_index,good_probes;
 reg probe_hit;
 reg signed [9:0] e0x,e0y,e1x,e1y;
 reg [10:0] center_bias_x,center_bias_y;
 reg signed [23:0] radial_x_q,radial_y_q;
 reg [21:0] radial;
 reg signed [19:0] dot_x_q,dot_y_q,cross_x_q,cross_y_q;
 reg [21:0] len_product;
 reg [20:0] collinear_limit;
 wire signed [20:0] dot=dot_x_q+dot_y_q;
 wire signed [20:0] cross_product=cross_x_q-cross_y_q;
 wire [20:0] abs_cross=cross_product<0?-cross_product:cross_product;
 wire [20:0] abs_dot=dot<0?-dot:dot;
 wire [10:0] len0=(e0x<0?-e0x:e0x)+(e0y<0?-e0y:e0y);
 wire [10:0] len1=(e1x<0?-e1x:e1x)+(e1y<0?-e1y:e1y);
 wire [8:0] row_rx=(state==READ || state==MASK_WAIT0 || state==MASK_WAIT1)?px-1'b1:state==GET?px:px+1'b1;
 wire [11:0] stats_address=state==INIT?init_address:{mem_label,mem_word};
 wire [16:0] mask_address=(state==P_WAIT || state==PROBE_WAIT0 || state==PROBE_WAIT1 || state==P_READ || state==NOISE_WAIT || state==NOISE_WAIT0 || state==NOISE_WAIT1 || state==NOISE_READ)?probe_address:pixel_index[16:0];
 function signed [11:0] projection(input integer d,input [8:0] x,y);
  reg signed [11:0] xx,yy;
  begin xx=$signed({3'b0,x});yy=$signed({3'b0,y});
   case(d)
    0:projection=xx;1:projection=2*xx+yy;2:projection=xx+yy;3:projection=xx+2*yy;
    4:projection=yy;5:projection=-xx+2*yy;6:projection=-xx+yy;7:projection=-2*xx+yy;
    8:projection=-xx;9:projection=-2*xx-yy;10:projection=-xx-yy;11:projection=-xx-2*yy;
    12:projection=-yy;13:projection=xx-2*yy;14:projection=xx-yy;15:projection=2*xx-yy;
   endcase
  end
 endfunction
 // Projection scores are derived from the support coordinates, not stored.
 // 16*(x9+y9) + count18 = 306 useful bits in a 320-bit/16-word record.
 function [319:0] one_pixel(input [8:0] x,y);
  reg [319:0] t;integer d;
  begin t=0;t[305:288]=1;
   for(d=0;d<16;d=d+1)t[d*18+:18]={y,x};
   one_pixel=t;
  end
 endfunction
 function [319:0] combine(input [319:0] a,b);
  reg [319:0] t;reg [18:0] count;integer d;
  reg signed [11:0] pa,pb;
  begin
   if(a[305:288]==0)combine=b;
   else if(b[305:288]==0)combine=a;
   else begin
    t=a;count={1'b0,a[305:288]}+b[305:288];t[305:288]=count[18]?18'h3ffff:count[17:0];
    for(d=0;d<16;d=d+1)begin
     pa=projection(d,a[d*18+:9],a[d*18+9+:9]);
     pb=projection(d,b[d*18+:9],b[d*18+9+:9]);
     if(pb>pa || (pb==pa && (b[d*18+9+:9]<a[d*18+9+:9] ||
        (b[d*18+9+:9]==a[d*18+9+:9] && b[d*18+:9]<a[d*18+:9]))))
      t[d*18+:18]=b[d*18+:18];
    end
    combine=t;
   end
  end
 endfunction
 function [9:0] distance(input [17:0] a,b);
  reg [9:0] dx,dy;
  begin dx=a[8:0]>b[8:0]?a[8:0]-b[8:0]:b[8:0]-a[8:0];
   dy=a[17:9]>b[17:9]?a[17:9]-b[17:9]:b[17:9]-a[17:9];distance=dx>dy?dx:dy;end
 endfunction
 function [10:0] bias(input [9:0] a,b);begin bias=a>b?a-b:b-a;end endfunction
 function duplicate(input [37:0] a,input [227:0] all_boxes);
  integer d;reg [37:0] b;reg [9:0] aw,ah,bw0,bh0;
  begin duplicate=0;aw=a[17:9]-a[8:0];ah=a[35:27]-a[26:18];
   for(d=0;d<6;d=d+1)begin b=all_boxes[d*38+:38];
    bw0=b[17:9]-b[8:0];bh0=b[35:27]-b[26:18];
    if(b[37:36]==a[37:36] && b[37:36]!=0 && {1'b0,a[8:0]}+10'd4>=b[8:0] &&
      {1'b0,a[26:18]}+10'd4>=b[26:18] && a[17:9]<={1'b0,b[17:9]}+10'd4 && a[35:27]<={1'b0,b[35:27]}+10'd4 &&
      ({2'b0,aw}<<2)>=3*{2'b0,bw0} && ({2'b0,ah}<<2)>=3*{2'b0,bh0})duplicate=1;
   end
  end
 endfunction
 wire [37:0] candidate={candidate_kind,ymax,ymin,xmax,xmin};
 wire valid_size=bw>=8 && bh>=8 && bw<W-4 && bh<H-4 && xmin>1 && ymin>1 &&
  xmax<W-2 && ymax<H-2 && stat_value[305:288]>=((bw+bh)>>1);
 wire [17:0] current_point=stat_value[point_index*18+:18];
 wire mask_write=sample_valid && state==IDLE && cap_count<W*H && !frame_start &&
                 (mask_pack_bit==9 || cap_count==W*H-1);
 wire [9:0] mask_write_data=mask_pack_bit==9?{sample_dark,mask_pack[9:1]}:
                          ({sample_dark,mask_pack[9:1]}>>(9-mask_pack_bit));
 v8_shape_ram #(10,10,4,13) mask_store(clk,mask_write,mask_pack_address,
                                     mask_word_address_q,mask_write_data,mask_word_q);
 wire [19:0] statistics_data;
 assign stats_q=statistics_data;
 v8_shape_ram #(20,9,3,8) statistics_store(clk,state==INIT || state==MW,
      stats_address,stats_address,state==INIT?20'd0:mem_shift[19:0],statistics_data);
 integer k,nx,ny;
 always @(posedge clk) begin
  // Exact floor(address/10): ceil(2^20/10)=104858 is exact for 17-bit
  // addresses. Product, quotient/remainder and RAM read are separate stages.
  mask_div_product_q<=mask_address*18'd104858;mask_address_q<=mask_address;
  mask_word_address_q<=mask_div_product_q[33:20];
  mask_bit_address_q<=mask_address_q-{mask_div_product_q[33:20],3'b000}-{mask_div_product_q[33:20],1'b0};
  mask_bit_q<=mask_bit_address_q;
  row_q<=rows[{!py[0],row_rx}];
  if(state==UPDATE || state==BG)rows[{py[0],px}]<=state==BG?6'd0:chosen;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin mask_pack<=0;mask_pack_bit<=0;mask_pack_address<=0;end
  else if(frame_start)begin mask_pack<=0;mask_pack_bit<=0;mask_pack_address<=0;end
  else if(sample_valid && state==IDLE && cap_count<W*H)begin
   mask_pack<={sample_dark,mask_pack[9:1]};
   if(mask_pack_bit==9)begin mask_pack_bit<=0;mask_pack_address<=mask_pack_address+1'b1;end
   else mask_pack_bit<=mask_pack_bit+1'b1;
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   state<=IDLE;noise_index<=0;error_reason<=0;cap_count<=0;pixel_index<=0;px<=0;py<=0;boxes<=0;pending_boxes<=0;
   result_valid<=0;overflow<=0;busy<=0;completed<=0;elapsed_cycles<=0;
   cache_valid<=0;cache_value<=0;cache_label<=0;child<=0;mem_shift<=0;stat_value<=0;
   init_address<=0;mem_label<=0;mem_word<=0;mem_return<=IDLE;next_label<=1;
   left_label<=0;root_work<=0;find_label<=0;chosen<=0;scan_label<=0;ni<=0;parent_q<=0;
   bw<=0;bh<=0;tolerance<=0;xmin<=0;xmax<=0;ymin<=0;ymax<=0;box_area<=0;
   point_index<=0;corner_count<=0;simplify_index<=0;point_q<=0;previous_support<=0;max_support_step<=0;dx2<=0;dy2<=0;min_r2<=0;max_r2<=0;
   candidate_kind<=0;edge_index<=0;probe_fraction<=1;edge_a<=0;edge_b<=0;
   probe_x<=0;probe_y<=0;probe_address<=0;neighbor_index<=0;good_probes<=0;probe_hit<=0;
   e0x<=0;e0y<=0;e1x<=0;e1y<=0;center_bias_x<=0;center_bias_y<=0;
   radial_x_q<=0;radial_y_q<=0;radial<=0;dot_x_q<=0;dot_y_q<=0;cross_x_q<=0;cross_y_q<=0;len_product<=0;collinear_limit<=0;
   apothem_dot<=0;apothem_square<=0;apothem_scaled<=0;min_apothem<=0;max_apothem<=0;
   for(k=0;k<6;k=k+1)scores[k]<=0;for(k=0;k<4;k=k+1)neighbors[k]<=0;
   for(k=0;k<16;k=k+1)corners[k]<=0;
  end else if(frame_start)begin
   if(busy)begin boxes<=0;result_valid<=0;overflow<=1;error_reason<=2;end
   state<=IDLE;busy<=0;cap_count<=0;cache_valid<=0;
  end else begin
   if(busy && elapsed_cycles!=22'h3fffff)elapsed_cycles<=elapsed_cycles+1'b1;
   if(sample_valid && state==IDLE && cap_count<W*H)cap_count<=cap_count+1'b1;
   if(frame_end && state==IDLE)begin
    result_valid<=0;boxes<=0;pending_boxes<=0;overflow<=0;cache_valid<=0;error_reason<=3;
    for(k=0;k<6;k=k+1)scores[k]<=0;
    if(cap_count==W*H)begin state<=INIT;init_address<=0;busy<=1;elapsed_cycles<=0;error_reason<=0;
     next_label<=1;pixel_index<=0;px<=0;py<=0;left_label<=0;end
   end
   case(state)
    INIT:begin
     if(init_address[3:0]==0)parent[init_address[11:4]]<=init_address[11:4];
     if(init_address==4095)state<=READ;else init_address<=init_address+1'b1;
    end
    READ:state<=MASK_WAIT0;
    MASK_WAIT0:state<=MASK_WAIT1;
    MASK_WAIT1:state<=GET;
    GET:if(!mask_q)state<=BG;else begin neighbors[0]<=left_label;neighbors[1]<=px==0 || py==0?6'd0:row_q;state<=N2;end
    N2:begin neighbors[2]<=py==0?6'd0:row_q;state<=N3;end
    N3:begin neighbors[3]<=px==W-1 || py==0?6'd0:row_q;ni<=0;root_work<=0;state<=NOISE_CHECK;end
    // Isolated mask pixels cannot satisfy any shape's size/closure checks.
    // Avoid allocating scarce temporary labels to them. Connected contours,
    // including one-pixel diagonal lines and two-pixel components, are retained.
    NOISE_CHECK:if(neighbors[0]!=0 || neighbors[1]!=0 || neighbors[2]!=0 || neighbors[3]!=0)state<=FS;
     else begin noise_index<=0;state<=NOISE_ADDR;end
    NOISE_ADDR:begin
     nx=px;ny=py;
     case(noise_index)
      0:nx=px+1;1:begin nx=px-1;ny=py+1;end
      2:ny=py+1;3:begin nx=px+1;ny=py+1;end
     endcase
     if(nx<0 || nx>=W || ny<0 || ny>=H)begin
      if(noise_index==3)state<=BG;else noise_index<=noise_index+1'b1;
     end else begin probe_address<=ny*W+nx;state<=NOISE_WAIT;end
    end
    NOISE_WAIT:state<=NOISE_WAIT0;
    NOISE_WAIT0:state<=NOISE_WAIT1;
    NOISE_WAIT1:state<=NOISE_READ;
    NOISE_READ:if(mask_q)state<=FS;
     else if(noise_index==3)state<=BG;
     else begin noise_index<=noise_index+1'b1;state<=NOISE_ADDR;end
    FS:if(neighbors[ni]==0)state<=NEXT;else begin find_label<=neighbors[ni];state<=FIND;end
    // Split the 256-way parent mux from root comparison/write enables.
    // A parent entry cannot change between this read and its decision cycle.
    FIND:begin parent_q<=parent[find_label];state<=FIND_WAIT;end
    FIND_WAIT:if(parent_q!=find_label)begin find_label<=parent_q;state<=FIND;end else begin
     if(root_work==0)root_work<=find_label;
     else if(root_work!=find_label)begin
      if(root_work<find_label)parent[find_label]<=root_work;
      else begin parent[root_work]<=find_label;root_work<=find_label;end
     end
     state<=NEXT;
    end
    NEXT:if(ni==3)state<=ALLOC;else begin ni<=ni+1'b1;state<=FS;end
    ALLOC:if(root_work!=0)begin chosen<=root_work;state<=MR;end
     else if(next_label!=0)begin chosen<=next_label;next_label<=next_label+1'b1;state<=MR;end
     else begin overflow<=1;error_reason<=1;pending_boxes<=0;state<=FINISH;end
    MR:if(cache_valid && cache_label==chosen)state<=UPDATE;
     else if(cache_valid)begin mem_label<=cache_label;mem_word<=0;mem_shift<=cache_value;mem_return<=LOAD;state<=MW;end
     else state<=LOAD;
    LOAD:begin mem_label<=chosen;mem_word<=0;mem_shift<=0;mem_return<=CACHE_GOT;state<=RD_ADDR;end
    CACHE_GOT:begin cache_value<=stat_value;cache_label<=chosen;cache_valid<=1;state<=UPDATE;end
    UPDATE:begin cache_value<=combine(cache_value,one_pixel(px,py));left_label<=chosen;state<=ADV;end
    BG:begin left_label<=0;state<=ADV;end
    ADV:if(pixel_index==W*H-1)begin
     scan_label<=1;
     if(cache_valid)begin mem_label<=cache_label;mem_word<=0;mem_shift<=cache_value;mem_return<=MERGE;state<=MW;end
     else state<=MERGE;
    end else begin
     pixel_index<=pixel_index+1'b1;
     if(px==W-1)begin px<=0;py<=py+1'b1;left_label<=0;end else px<=px+1'b1;
     state<=READ;
    end
    RD_ADDR:state<=RD_DATA;
    RD_DATA:begin mem_shift<={stats_q,mem_shift[319:20]};
     if(mem_word==15)begin stat_value<={stats_q,mem_shift[319:20]};state<=mem_return;end
     else begin mem_word<=mem_word+1'b1;state<=RD_ADDR;end
    end
    MW:begin mem_shift<=mem_shift>>20;
     if(mem_word==15)state<=mem_return;else mem_word<=mem_word+1'b1;
    end
    MERGE:if(scan_label==next_label)begin scan_label<=1;state<=CLASS_REQ;end
     else if(parent[scan_label]==scan_label)scan_label<=scan_label+1'b1;
     else begin find_label<=parent[scan_label];state<=MFIND;end
    MFIND:begin parent_q<=parent[find_label];state<=MFIND_WAIT;end
    MFIND_WAIT:if(parent_q!=find_label)begin find_label<=parent_q;state<=MFIND;end else state<=CHILD_REQ;
    CHILD_REQ:begin mem_label<=scan_label;mem_word<=0;mem_shift<=0;mem_return<=CHILD_GOT;state<=RD_ADDR;end
    CHILD_GOT:begin child<=stat_value;state<=ROOT_REQ;end
    ROOT_REQ:begin mem_label<=find_label;mem_word<=0;mem_shift<=0;mem_return<=ROOT_GOT;state<=RD_ADDR;end
    ROOT_GOT:begin mem_label<=find_label;mem_word<=0;mem_shift<=combine(stat_value,child);mem_return<=MERGE_NEXT;state<=MW;end
    MERGE_NEXT:begin scan_label<=scan_label+1'b1;state<=MERGE;end
    CLASS_REQ:if(scan_label==next_label)state<=FINISH;
     else if(parent[scan_label]!=scan_label)state<=CLASS_NEXT;
     else begin mem_label<=scan_label;mem_word<=0;mem_shift<=0;mem_return<=CLASS_GEOM;state<=RD_ADDR;end
    CLASS_GEOM:begin
     xmin<=stat_value[8*18+:9];xmax<=stat_value[0+:9];ymin<=stat_value[12*18+9+:9];ymax<=stat_value[4*18+9+:9];
     bw<={1'b0,stat_value[0+:9]}-stat_value[8*18+:9];bh<={1'b0,stat_value[4*18+9+:9]}-stat_value[12*18+9+:9];
     box_area<=({1'b0,stat_value[0+:9]}-stat_value[8*18+:9])*({1'b0,stat_value[4*18+9+:9]}-stat_value[12*18+9+:9]);
     point_index<=0;corner_count<=0;max_support_step<=0;min_r2<=22'h3fffff;max_r2<=0;min_apothem<=30'h3fffffff;max_apothem<=0;candidate_kind<=0;state<=POINT;
    end
    POINT:begin
     tolerance<=(bw<20 && bh<20)?9'd1:(bw<40 && bh<40)?9'd2:(((bw<bh?bw:bh)>>6)<<1)+4;point_q<=current_point;
     dx2<=2*$signed({3'b0,current_point[8:0]})-$signed({2'b0,xmin})-$signed({2'b0,xmax});
     dy2<=2*$signed({3'b0,current_point[17:9]})-$signed({2'b0,ymin})-$signed({2'b0,ymax});
     state<=RAD_MUL;
    end
    RAD_MUL:begin
     radial_x_q<=dx2*dx2;radial_y_q<=dy2*dy2;
     case(point_index)
      0:apothem_dot<=dx2;1:apothem_dot<=2*dx2+dy2;2:apothem_dot<=dx2+dy2;3:apothem_dot<=dx2+2*dy2;
      4:apothem_dot<=dy2;5:apothem_dot<=-dx2+2*dy2;6:apothem_dot<=-dx2+dy2;7:apothem_dot<=-2*dx2+dy2;
      8:apothem_dot<=-dx2;9:apothem_dot<=-2*dx2-dy2;10:apothem_dot<=-dx2-dy2;11:apothem_dot<=-dx2-2*dy2;
      12:apothem_dot<=-dy2;13:apothem_dot<=dx2-2*dy2;14:apothem_dot<=dx2-dy2;15:apothem_dot<=2*dx2-dy2;
     endcase
     state<=RAD_SUM;
    end
    RAD_SUM:begin radial<=radial_x_q+radial_y_q;apothem_square<=apothem_dot*apothem_dot;state<=APO_SCALE;end
    APO_SCALE:begin
     apothem_scaled<=point_index[0]?({4'b0,apothem_square}<<1):point_index[1]?({4'b0,apothem_square}<<2)+apothem_square:({4'b0,apothem_square}<<3)+({4'b0,apothem_square}<<1);
     state<=ACC;
    end
    ACC:begin
     if(point_index!=0 && distance(point_q,previous_support)>max_support_step)max_support_step<=distance(point_q,previous_support);
     previous_support<=point_q;
     if(corner_count==0 || distance(point_q,corners[corner_count-1])>tolerance)begin corners[corner_count]<=point_q;corner_count<=corner_count+1'b1;end
     if(radial<min_r2)min_r2<=radial;if(radial>max_r2)max_r2<=radial;
     if(apothem_scaled<min_apothem)min_apothem<=apothem_scaled;if(apothem_scaled>max_apothem)max_apothem<=apothem_scaled;
     if(point_index==15)state<=CLOSE;else begin point_index<=point_index+1'b1;state<=POINT;end
    end
    CLOSE:begin
     if(distance(previous_support,stat_value[17:0])>max_support_step)max_support_step<=distance(previous_support,stat_value[17:0]);
     if(corner_count>1 && distance(corners[corner_count-1],corners[0])<=tolerance)corner_count<=corner_count-1'b1;
     state<=KIND;
    end
    KIND:if(!valid_size)state<=CLASS_NEXT;
     else if(corner_count>=(bw<56 || bh<56?6:10) &&
      max_support_step<=(bw<40 && bh<40?((bw>bh?bw:bh)>>1)+3:(((bw<bh?bw:bh)*3)>>3)+2) &&
      bw*3>=bh*2 && bh*3>=bw*2 && max_r2*5<=min_r2*9 &&
      {3'b0,max_apothem}*5<={3'b0,min_apothem}*9)begin candidate_kind<=1;state<=INSERT;end
     else if(corner_count>=3 && corner_count<=9)begin simplify_index<=0;state<=SIMPLIFY_VEC;end
     else state<=CLASS_NEXT;
    SIMPLIFY_VEC:begin
     e0x<=$signed({2'b0,corners[simplify_index][8:0]})-$signed({2'b0,corners[simplify_index==0?corner_count-1:simplify_index-1][8:0]});
     e0y<=$signed({2'b0,corners[simplify_index][17:9]})-$signed({2'b0,corners[simplify_index==0?corner_count-1:simplify_index-1][17:9]});
     e1x<=$signed({2'b0,corners[simplify_index+1==corner_count?0:simplify_index+1][8:0]})-$signed({2'b0,corners[simplify_index==0?corner_count-1:simplify_index-1][8:0]});
     e1y<=$signed({2'b0,corners[simplify_index+1==corner_count?0:simplify_index+1][17:9]})-$signed({2'b0,corners[simplify_index==0?corner_count-1:simplify_index-1][17:9]});
     state<=SIMPLIFY_MUL;
    end
    SIMPLIFY_MUL:begin cross_x_q<=e0x*e1y;cross_y_q<=e0y*e1x;collinear_limit<=((bw<20 && bh<20)?(tolerance<2?9'd2:tolerance):(tolerance<4?9'd4:tolerance))*len1;state<=SIMPLIFY_CHECK;end
    SIMPLIFY_CHECK:if(corner_count>3 && abs_cross<=collinear_limit)state<=SIMPLIFY_REMOVE;
     else if(simplify_index+1==corner_count)begin
      if(corner_count==3 || corner_count==4)begin candidate_kind<=corner_count==3?3:2;state<=POLY_VEC;end
      else state<=CLASS_NEXT;
     end else begin simplify_index<=simplify_index+1'b1;state<=SIMPLIFY_VEC;end
    SIMPLIFY_REMOVE:begin
     for(k=0;k<15;k=k+1)if(k>=simplify_index && k+1<corner_count)corners[k]<=corners[k+1];
     corner_count<=corner_count-1'b1;simplify_index<=0;state<=SIMPLIFY_VEC;
    end
    POLY_VEC:begin
     e0x<=$signed({2'b0,corners[1][8:0]})-$signed({2'b0,corners[0][8:0]});
     e0y<=$signed({2'b0,corners[1][17:9]})-$signed({2'b0,corners[0][17:9]});
     e1x<=$signed({2'b0,corners[2][8:0]})-$signed({2'b0,corners[1][8:0]});
     e1y<=$signed({2'b0,corners[2][17:9]})-$signed({2'b0,corners[1][17:9]});
     center_bias_x<=bias({2'b0,corners[0][8:0]}+corners[2][8:0],{2'b0,corners[1][8:0]}+corners[3][8:0]);
     center_bias_y<=bias({2'b0,corners[0][17:9]}+corners[2][17:9],{2'b0,corners[1][17:9]}+corners[3][17:9]);state<=POLY_MUL;
    end
    POLY_MUL:begin dot_x_q<=e0x*e1x;dot_y_q<=e0y*e1y;cross_x_q<=e0x*e1y;cross_y_q<=e0y*e1x;len_product<=len0*len1;state<=POLY_CHECK;end
    POLY_CHECK:if(candidate_kind==2 && ((abs_dot<<2)>len_product || center_bias_x>((bw+bh)>>3)+2 || center_bias_y>((bw+bh)>>3)+2))state<=CLASS_NEXT;
     else if(candidate_kind==3 && (abs_cross<<1)<box_area)state<=CLASS_NEXT;
     else begin edge_index<=0;probe_fraction<=1;good_probes<=0;state<=P_PREP;end
    P_PREP:begin edge_a<=corners[edge_index];edge_b<=corners[edge_index+1==corner_count?0:edge_index+1];state<=P_CENTER;end
    P_CENTER:begin
     case(probe_fraction)
      1:begin probe_x<=(3*{2'b0,edge_a[8:0]}+edge_b[8:0]+2)>>2;probe_y<=(3*{2'b0,edge_a[17:9]}+edge_b[17:9]+2)>>2;end
      2:begin probe_x<=({1'b0,edge_a[8:0]}+edge_b[8:0]+1)>>1;probe_y<=({1'b0,edge_a[17:9]}+edge_b[17:9]+1)>>1;end
      3:begin probe_x<=({2'b0,edge_a[8:0]}+3*{2'b0,edge_b[8:0]}+2)>>2;probe_y<=({2'b0,edge_a[17:9]}+3*{2'b0,edge_b[17:9]}+2)>>2;end
     endcase
     neighbor_index<=0;probe_hit<=0;state<=P_ADDR;
    end
    P_ADDR:begin nx=probe_x+(neighbor_index%5)-2;ny=probe_y+(neighbor_index/5)-2;
     if(nx<0 || nx>=W || ny<0 || ny>=H)begin
      if(neighbor_index==24)state<=P_NEXT;else neighbor_index<=neighbor_index+1'b1;
     end else begin probe_address<=ny*W+nx;state<=P_WAIT;end
    end
    P_WAIT:state<=PROBE_WAIT0;
    PROBE_WAIT0:state<=PROBE_WAIT1;
    PROBE_WAIT1:state<=P_READ;
    P_READ:if(mask_q)begin probe_hit<=1;state<=P_NEXT;end
     else if(neighbor_index==24)state<=P_NEXT;
     else begin neighbor_index<=neighbor_index+1'b1;state<=P_ADDR;end
    P_NEXT:begin
     if(probe_hit)good_probes<=good_probes+1'b1;
     if(probe_fraction==3)begin
      probe_fraction<=1;
      if(edge_index+1==corner_count)begin
       if(good_probes+probe_hit>=corner_count*3-1)state<=INSERT;else state<=CLASS_NEXT;
      end else begin edge_index<=edge_index+1'b1;state<=P_PREP;end
     end else begin probe_fraction<=probe_fraction+1'b1;state<=P_CENTER;end
    end
    INSERT:begin
     if(!duplicate(candidate,pending_boxes))begin
      if(box_area>scores[0])begin scores[0]<=box_area;scores[1]<=scores[0];scores[2]<=scores[1];scores[3]<=scores[2];scores[4]<=scores[3];scores[5]<=scores[4];pending_boxes[0+:38]<=candidate;pending_boxes[38+:38]<=pending_boxes[0+:38];pending_boxes[76+:38]<=pending_boxes[38+:38];pending_boxes[114+:38]<=pending_boxes[76+:38];pending_boxes[152+:38]<=pending_boxes[114+:38];pending_boxes[190+:38]<=pending_boxes[152+:38];end
      else if(box_area>scores[1])begin scores[1]<=box_area;scores[2]<=scores[1];scores[3]<=scores[2];scores[4]<=scores[3];scores[5]<=scores[4];pending_boxes[38+:38]<=candidate;pending_boxes[76+:38]<=pending_boxes[38+:38];pending_boxes[114+:38]<=pending_boxes[76+:38];pending_boxes[152+:38]<=pending_boxes[114+:38];pending_boxes[190+:38]<=pending_boxes[152+:38];end
      else if(box_area>scores[2])begin scores[2]<=box_area;scores[3]<=scores[2];scores[4]<=scores[3];scores[5]<=scores[4];pending_boxes[76+:38]<=candidate;pending_boxes[114+:38]<=pending_boxes[76+:38];pending_boxes[152+:38]<=pending_boxes[114+:38];pending_boxes[190+:38]<=pending_boxes[152+:38];end
      else if(box_area>scores[3])begin scores[3]<=box_area;scores[4]<=scores[3];scores[5]<=scores[4];pending_boxes[114+:38]<=candidate;pending_boxes[152+:38]<=pending_boxes[114+:38];pending_boxes[190+:38]<=pending_boxes[152+:38];end
      else if(box_area>scores[4])begin scores[4]<=box_area;scores[5]<=scores[4];pending_boxes[152+:38]<=candidate;pending_boxes[190+:38]<=pending_boxes[152+:38];end
      else if(box_area>scores[5])begin scores[5]<=box_area;pending_boxes[190+:38]<=candidate;end
     end
     state<=CLASS_NEXT;
    end
    CLASS_NEXT:begin scan_label<=scan_label+1'b1;state<=CLASS_REQ;end
    FINISH:begin boxes<=pending_boxes;result_valid<=!overflow;busy<=0;completed<=completed+1'b1;state<=IDLE;end
   endcase
  end
 end
endmodule
''',encoding='utf-8')
print('Generated V8 support-contour detector')
