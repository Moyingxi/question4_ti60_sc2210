`timescale 1ns/1ps
module tb_v8_shape_edges;
 reg clk=0,rst_n=0,fs=0,sv=0;always #5 clk=~clk;
 reg [7:0] gray=0;reg [1:0] setting=1;reg [9:0] x=0,y=0;wire valid,edge_pixel;
 v8_shape_edges #(128,96) dut(clk,rst_n,fs,sv,gray,setting,x,y,valid,edge_pixel);
 reg expected[0:64*48-1];reg [7:0] image[0:128*96-1];
 integer f,n,i,out_count=0,edge_count=0,edge_distance,v,xx,yy,limit;reg foreground,outline;
 function integer ab(input integer a);begin ab=a<0?-a:a;end endfunction
 always @(posedge clk)if(rst_n && valid)begin
  if(f!=4 && edge_pixel!==expected[out_count])$fatal(1,"independent 2x2 mask mismatch at %0d case%0d",out_count,f);
  out_count=out_count+1;if(edge_pixel)edge_count=edge_count+1;
 end
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(f=0;f<10;f=f+1)begin
   setting=f>=6?f-6:1;limit=32-8*setting;
   for(i=0;i<64*48;i=i+1)expected[i]=0;
   for(n=0;n<128*96;n=n+1)begin
    xx=n%128;yy=n/128;
    foreground=xx>=21 && xx<=105 && yy>=17 && yy<=77;
    outline=foreground && (xx==21 || xx==105 || yy==17 || yy==77);
    image[n]=f==0?(foreground?20:220):f==1?(foreground?220:20):f==2?(foreground?190:230):f==3?(outline?20:220):(foreground?20:220);
    if(f==5)begin
     edge_distance=ab(xx-21)+(yy<17?17-yy:yy>77?yy-77:0);
     v=ab(xx-105)+(yy<17?17-yy:yy>77?yy-77:0);if(v<edge_distance)edge_distance=v;
     v=ab(yy-17)+(xx<21?21-xx:xx>105?xx-105:0);if(v<edge_distance)edge_distance=v;
     v=ab(yy-77)+(xx<21?21-xx:xx>105?xx-105:0);if(v<edge_distance)edge_distance=v;
     image[n]=edge_distance<3?160+20*edge_distance:220;
    end
    if(f>=6)image[n]=foreground?200:220;
   end
   for(n=0;n<128*96;n=n+1)begin
    xx=n%128;yy=n/128;
    if((xx>=2 && ab(int'(image[n])-int'(image[n-2]))>=limit) ||
       (yy>=2 && ab(int'(image[n])-int'(image[n-256]))>=limit))
       expected[(yy/2)*64+xx/2]=1;
   end
   @(negedge clk);fs=1;@(negedge clk);fs=0;out_count=0;edge_count=0;
   for(n=0;n<128*96;n=n+1)begin
    @(negedge clk);x=n%128;y=n/128;sv=!(f==4 && y==18);gray=image[n];
   end
   @(negedge clk);sv=0;repeat(12)@(negedge clk);
   if(f!=4 && out_count!=64*48)$fatal(1,"incomplete 480-style mask %0d",out_count);
   if(f<4 && edge_count<50)$fatal(1,"visible contour lost");
   if(f==4 && out_count!=64*48-1)$fatal(1,"missing row not invalidated %0d",out_count);
   if(f>=6 && ((setting<2 && edge_count!=0)||(setting>=2 && edge_count<50)))$fatal(1,"contrast threshold direction wrong");
  end
  $display("PASS shape edges: exact independent 2x2 pooling, thin hollow outlines, polarity/blur, four sensitivities, missing-row rejection");$finish;
 end
endmodule
