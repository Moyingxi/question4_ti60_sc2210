`timescale 1ns/1ps
module tb_v8_shape_ram;
 reg clk=0;always #5 clk=~clk;
 reg we10=0,we20=0;reg [13:0] wa10=0,ra10=0;reg [11:0] wa20=0,ra20=0;
 reg [9:0] d10=0;reg [19:0] d20=0;wire [9:0] q10;wire [19:0] q20;
 v8_shape_ram #(10,10,4,13) mask(clk,we10,wa10,ra10,d10,q10);
 v8_shape_ram #(20,9,3,8) stats(clk,we20,wa20,ra20,d20,q20);
 function [9:0] p10(input integer a);begin p10=(a*37)^(a>>3)^10'h295;end endfunction
 function [19:0] p20(input integer a);begin p20=(a*137)^(a<<7)^20'hcab35;end endfunction
 integer i,a10,a20;reg [31:0] rng=32'h480270ff;
 initial begin
  for(i=0;i<13312;i=i+1)begin
   @(negedge clk);we10=1;wa10=i;d10=p10(i);
   we20=i<4096;wa20=i;d20=p20(i);
  end
  @(negedge clk);we10=0;we20=0;
  for(i=0;i<20000;i=i+1)begin
   rng=(rng<<1)^({32{rng[31]}}&32'h04c11db7);
   a10=i<13312?i:rng%13312;a20=i<4096?i:(rng>>2)%4096;
   ra10=a10;ra20=a20;
   @(posedge clk);#0.001;
   if(q10!==p10(a10) || q20!==p20(a20))$fatal(1,"native RAM mode/bank/read latency mismatch mask%0d stats%0d",a10,a20);
   @(negedge clk);
  end
  $display("PASS native RAM10 1024x10 and 512x20 banks, all addresses plus random reads, exact synchronous latency");$finish;
 end
endmodule
