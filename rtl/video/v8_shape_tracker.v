`timescale 1ns/1ps
// Six associated tracks. Brief valid-frame misses are tolerated, but an
// invalid input/configuration/deadline clears all tracks immediately.
module v8_shape_tracker(
 input clk,rst_n,update,clear,input [227:0] boxes,
 output reg [227:0] tracked_boxes,output reg tracked_valid
);
 localparam IDLE=0,START=1,SEARCH=2,MATCH=3,ALLOC=4,NEXT=5,AGE=6,COMMIT=7;
 reg [2:0] state;
 reg [227:0] incoming;
 reg [37:0] tracks[0:5];reg [2:0] misses[0:5];
 reg [1:0] pending_kind[0:5];reg [2:0] pending_count[0:5];
 reg [37:0] pending_position[0:5];reg [1:0] position_count[0:5];
 reg [5:0] used;
 reg [2:0] object_index,slot;
 reg [2:0] best;
 reg [10:0] best_distance;
 wire [37:0] object_box=incoming[object_index*38+:38];
 function [10:0] separation(input [37:0] a,b);
  reg [9:0] ax,bx,ay,by;reg [10:0] dx,dy;
  begin ax={1'b0,a[8:0]}+a[17:9];bx={1'b0,b[8:0]}+b[17:9];
   ay={1'b0,a[26:18]}+a[35:27];by={1'b0,b[26:18]}+b[35:27];
   dx=ax>bx?ax-bx:bx-ax;dy=ay>by?ay-by:by-ay;separation=dx>dy?dx:dy;
  end
 endfunction
 function near_bounds(input [37:0] a,b);
  integer n;reg [9:0] difference;
  begin near_bounds=1;for(n=0;n<4;n=n+1)begin
   difference=a[n*9+:9]>b[n*9+:9]?a[n*9+:9]-b[n*9+:9]:b[n*9+:9]-a[n*9+:9];
   if(difference>4)near_bounds=0;
  end end
 endfunction
 function overlap_gate(input [37:0] a,b);
  reg [9:0] aw,ah,bw,bh;
  begin aw=a[17:9]-a[8:0];ah=a[35:27]-a[26:18];bw=b[17:9]-b[8:0];bh=b[35:27]-b[26:18];
   overlap_gate=({1'b0,a[8:0]}<=b[17:9]+10'd4) && ({1'b0,b[8:0]}<=a[17:9]+10'd4) &&
    ({1'b0,a[26:18]}<=b[35:27]+10'd4) && ({1'b0,b[26:18]}<=a[35:27]+10'd4) &&
    (aw<<1)>=bw && (bw<<1)>=aw && (ah<<1)>=bh && (bh<<1)>=ah;
  end
 endfunction
 // Three consistent position observations precede this update. Adopt the
 // confirmed bounds beyond the deadband to avoid multi-frame zoom catch-up.
 function [37:0] smooth(input [37:0] a,b);
  reg [37:0] t;integer n;reg [9:0] av,bv;
  begin t=b;for(n=0;n<4;n=n+1)begin av={1'b0,a[n*9+:9]};bv={1'b0,b[n*9+:9]};
   if(bv>av+4 || av>bv+4)t[n*9+:9]=bv;else t[n*9+:9]=av;
  end smooth=t;end
 endfunction
 wire [10:0] distance=separation(object_box,tracks[slot]);
 integer k;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;incoming<=0;tracked_boxes<=0;tracked_valid<=0;used<=0;
   object_index<=0;slot<=0;best<=6;best_distance<=2047;
   for(k=0;k<6;k=k+1)begin tracks[k]<=0;misses[k]<=0;pending_kind[k]<=0;pending_count[k]<=0;pending_position[k]<=0;position_count[k]<=0;end
  end else if(clear)begin
   state<=IDLE;tracked_boxes<=0;tracked_valid<=0;
   for(k=0;k<6;k=k+1)begin tracks[k]<=0;misses[k]<=0;pending_kind[k]<=0;pending_count[k]<=0;pending_position[k]<=0;position_count[k]<=0;end
  end else case(state)
   IDLE:if(update)begin incoming<=boxes;object_index<=0;used<=0;state<=START;end
   START:if(object_box[37:36]==0)state<=NEXT;
    else begin slot<=0;best<=6;best_distance<=2047;state<=SEARCH;end
   SEARCH:begin
    if(tracks[slot][37:36]!=0 && !used[slot] && overlap_gate(object_box,tracks[slot]) && distance<=64 && distance<best_distance)begin best<=slot;best_distance<=distance;end
    if(slot==5)state<=MATCH;else slot<=slot+1'b1;
   end
   MATCH:if(best==6)begin slot<=0;state<=ALLOC;end
    else begin
     used[best]<=1;misses[best]<=0;
     if(tracks[best][37:36]==object_box[37:36])begin
      pending_count[best]<=0;
      if(near_bounds(object_box,pending_position[best]))begin
       if(position_count[best]==2)begin tracks[best]<=smooth(tracks[best],object_box);position_count[best]<=0;end
       else position_count[best]<=position_count[best]+1'b1;
      end else begin pending_position[best]<=object_box;position_count[best]<=1;end
     end
     else if(pending_count[best]!=0 && pending_kind[best]==object_box[37:36])begin
      if(pending_count[best]==5)begin tracks[best]<=smooth(tracks[best],object_box);pending_count[best]<=0;position_count[best]<=0;end
      else pending_count[best]<=pending_count[best]+1'b1;
     end else begin pending_kind[best]<=object_box[37:36];pending_count[best]<=1;position_count[best]<=0;end
     state<=NEXT;
    end
   ALLOC:if(tracks[slot][37:36]==0 && !used[slot])begin tracks[slot]<=object_box;misses[slot]<=0;used[slot]<=1;pending_count[slot]<=0;pending_position[slot]<=object_box;position_count[slot]<=0;state<=NEXT;end
    else if(slot==5)state<=NEXT;else slot<=slot+1'b1;
   NEXT:if(object_index==5)begin slot<=0;state<=AGE;end
    else begin object_index<=object_index+1'b1;state<=START;end
   AGE:begin
    if(tracks[slot][37:36]!=0 && !used[slot])begin
     pending_count[slot]<=0;position_count[slot]<=0;
     if(misses[slot]==3)begin tracks[slot]<=0;pending_count[slot]<=0;position_count[slot]<=0;end
     else misses[slot]<=misses[slot]+1'b1;
    end
    if(slot==5)state<=COMMIT;else slot<=slot+1'b1;
   end
   COMMIT:begin tracked_boxes<={tracks[5],tracks[4],tracks[3],tracks[2],tracks[1],tracks[0]};
    tracked_valid<=tracks[5][37:36]!=0 || tracks[4][37:36]!=0 || tracks[0][37:36]!=0 || tracks[1][37:36]!=0 || tracks[2][37:36]!=0 || tracks[3][37:36]!=0;state<=IDLE;
   end
  endcase
 end
endmodule
