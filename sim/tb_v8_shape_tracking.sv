`timescale 1ns/1ps
module tb_v8_shape_tracking;
 reg clk=0,rst_n=0,update=0,clear=0;always #5 clk=~clk;
 reg [227:0] input_boxes=0;wire [227:0] output_boxes;wire valid;
 v8_shape_tracker dut(clk,rst_n,update,clear,input_boxes,output_boxes,valid);
 reg [11:0] x=0;reg [10:0] y=0;wire hit;wire [23:0] color;
 v8_shape_overlay overlay(x,y,1'b1,valid,1'b0,2'd1,output_boxes,hit,color);
 function [37:0] box(input [1:0] kind,input [8:0] x0,x1,y0,y1);begin box={kind,9'(y1*2),9'(y0*2),9'(x1*2),9'(x0*2)};end endfunction
 reg [37:0] a,b;integer i,text_pixels;
 task frame(input [227:0] value);
  begin @(negedge clk);input_boxes=value;update=1;@(negedge clk);update=0;repeat(120)@(negedge clk);end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;a=box(1,20,70,20,70);b=box(2,120,170,30,80);
  frame({152'd0,b,a});if(!valid || output_boxes[75:0]!={b,a})$fatal(1,"initial tracks");
  frame({152'd0,a,b});if(output_boxes[75:0]!={b,a})$fatal(1,"rank reordering broke association");
  for(i=0;i<20;i=i+1)begin
   frame({152'd0,b,box(1,i[0]?22:18,i[0]?72:68,i[0]?22:18,i[0]?72:68)});
   if(output_boxes[75:0]!={b,a})$fatal(1,"stationary quantization jitter moved box");
  end
  frame({152'd0,b,box(1,28,78,28,78)});
  if(output_boxes[75:0]!={b,a})$fatal(1,"one-frame coordinate outlier moved box");
  for(i=0;i<3;i=i+1)begin frame(0);if(!valid || output_boxes[75:0]!={b,a})$fatal(1,"brief miss flicker");end
  frame(0);if(valid || output_boxes!=0)$fatal(1,"stale detections not expired");
  frame({190'd0,a});
  for(i=0;i<8;i=i+1)begin
   frame({190'd0,box(i[0]?1:2,20,70,20,70)});
   if(output_boxes[37:36]!=1)$fatal(1,"alternating circle/rectangle noise changed class");
  end
  for(i=0;i<5;i=i+1)begin frame({190'd0,box(3,20,70,20,70)});if(output_boxes[37:36]!=1)$fatal(1,"unconfirmed class changed");end
  frame({190'd0,box(3,20,70,20,70)});if(output_boxes[37:36]!=3)$fatal(1,"six-frame triangle class confirmation");
  x=80;y=430;#1;if(!hit || color!=24'hffb030)$fatal(1,"triangle box color");
  text_pixels=0;
  for(i=0;i<96*32;i=i+1)begin x=80+i%96;y=316+i/96;#1;if(hit && color==24'hffb030)text_pixels=text_pixels+1;end
  if(text_pixels<100)$fatal(1,"triangle Chinese three-character label missing");
  @(negedge clk);clear=1;@(negedge clk);clear=0;#1;
  if(valid || output_boxes!=0)$fatal(1,"invalid/configuration input retained stale annotation");
  a=box(1,20,30,20,30);b=box(1,20,30,34,44);
  frame({190'd0,a});frame({190'd0,b});
  if(output_boxes[37:0]!=a || output_boxes[75:38]!=b)$fatal(1,"nearby nonoverlapping objects were cross-associated");
  @(negedge clk);clear=1;@(negedge clk);clear=0;
  frame({box(3,180,200,80,100),box(3,180,200,20,40),box(2,100,130,80,100),box(2,100,130,20,40),box(1,20,40,80,100),box(1,20,40,20,40)});
  if(output_boxes!==input_boxes)$fatal(1,"six simultaneous tracks not retained");
  x=720;y=620;#1;if(!hit || color!=24'hffb030)$fatal(1,"sixth triangle box not rendered");
  frame({input_boxes[37:0],input_boxes[227:38]});
  if(output_boxes[227:190]!=box(3,180,200,80,100))$fatal(1,"six-target reordering lost association");
  @(negedge clk);clear=1;@(negedge clk);clear=0;
  a=box(1,100,150,50,100);b=box(1,80,170,30,120);
  frame({190'd0,a});
  frame({190'd0,b});frame({190'd0,b});
  if(output_boxes[37:0]!=a)$fatal(1,"unconfirmed zoom changed position");
  frame({190'd0,b});
  if(output_boxes[37:0]!=b)$fatal(1,"stable forward zoom requires excessive catch-up");
  frame({190'd0,a});frame({190'd0,a});frame({190'd0,a});
  if(output_boxes[37:0]!=a)$fatal(1,"backward zoom failed to reacquire without shaking");
  $display("PASS stable tracking: position deadband, coordinate outlier, overlap association, alternating class rejection, six-frame class confirmation, expiry, invalidation, rapid forward/backward apparent-size recovery");$finish;
 end
endmodule
