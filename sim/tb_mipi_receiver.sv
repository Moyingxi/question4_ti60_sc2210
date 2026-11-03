`timescale 1ns/1ps
// Receiver investigation: four synchronized RAW8 lanes at the byte interface.
module tb_mipi_receiver #(
 parameter GROUPS=480, LINES=3, FRAMES=260,
 parameter BYTE_DELAY=0, LP_DELAY=0, CHECK_PIXELS=1, TAIL_WORDS=0, ALIGN_LP=1
);
reg clk=0, rst=1, lp_p=1, lp_n=1;
reg [31:0] lanes=0;
reg [31:0] lanes_q=0;
reg [7:0] lp_p_pipe=8'hff,lp_n_pipe=8'hff;
always @(posedge clk)begin
 lanes_q<=lanes;lp_p_pipe<={lp_p_pipe[6:0],lp_p};lp_n_pipe<={lp_n_pipe[6:0],lp_n};
end
wire [31:0] dut_lanes=BYTE_DELAY ? lanes_q : lanes;
wire dut_lp_p,dut_lp_n;
generate if(ALIGN_LP)begin
 v8_csi_lp_align align_lp(.clk(clk),.rst(rst),.lp_p(lp_p),.lp_n(lp_n),
  .rx_lp_p(dut_lp_p),.rx_lp_n(dut_lp_n));
end else if(LP_DELAY==0)begin
 assign dut_lp_p=lp_p;assign dut_lp_n=lp_n;
end else begin
 assign dut_lp_p=lp_p_pipe[LP_DELAY-1];assign dut_lp_n=lp_n_pipe[LP_DELAY-1];
end endgenerate
wire [3:0] vs,hs; wire de; wire[47:0] raw,diag;
always #5 clk=~clk;
MIPIRx4LaneFre dut(.sclk_i(clk),.srst_i(rst),.mipi_rx_byteclk_i(clk),
 .mipi_rx_d0_i(dut_lanes[7:0]),.mipi_rx_d1_i(dut_lanes[15:8]),
 .mipi_rx_d2_i(dut_lanes[23:16]),.mipi_rx_d3_i(dut_lanes[31:24]),
 .mipi_rx_clk_lp_p_i(1'b0),.mipi_rx_clk_lp_n_i(1'b0),
 .mipi_rx_d0_lp_p_i(dut_lp_p),.mipi_rx_d0_lp_n_i(dut_lp_n),
 .VSYNC(vs),.HSYNC(hs),.DE(de),.DAT(raw),.RX_DIAG(diag));
function automatic [7:0] rev(input[7:0] b);
 integer i;begin for(i=0;i<8;i=i+1)rev[i]=b[7-i];end
endfunction
function automatic [31:0] payload(input integer frame_id,input integer group_id);
 begin payload={8'(frame_id+group_id),8'(frame_id*3+group_id*5),
                8'(frame_id*7+group_id*11),8'(frame_id*13+group_id*17)};end
endfunction
// Header ECC parity masks cross-checked against the bundled receiver netlist.
function automatic [31:0] header(input[7:0] di,input[15:0] wc);
 reg[23:0] d;reg[7:0] ecc;
 begin
  d={wc,di};ecc=0;
  ecc[0]=^(d&24'hf12cb7);ecc[1]=^(d&24'hf2555b);
  ecc[2]=^(d&24'h749a6d);ecc[3]=^(d&24'hb8e38e);
  ecc[4]=^(d&24'hdf03f0);ecc[5]=^(d&24'heffc00);
  header={ecc,d};
 end
endfunction
task automatic word(input[31:0] w);
 begin @(posedge clk);#0.5;lanes={rev(w[31:24]),rev(w[23:16]),rev(w[15:8]),rev(w[7:0])};end
endtask
task automatic start_packet;
 begin
  @(negedge clk); lp_p=0;lp_n=1;lanes=0;
  repeat(8) @(negedge clk);
  lp_n=0;repeat(16) @(negedge clk);
  word(32'hb8b8b8b8);
 end
endtask
task automatic end_packet;
 begin
  // LP begins immediately after the short header / long-packet CRC word.
  // Extra zero words here previously masked byte/LP phase misalignment.
  repeat(TAIL_WORDS)word(0);
  @(posedge clk);#0.5;
  lp_p=1;lp_n=1;lanes=0;repeat(20) @(negedge clk);
 end
endtask
integer f,i,line,frames=0,pixels=0,headers=0,valid_run=0,line_runs=0;reg last_vs=0;
always @(posedge clk) begin
 if(vs[0]&&!last_vs)frames=frames+1;
 last_vs=vs[0];
 if(de&&hs[0])begin
  valid_run=valid_run+1;
  if(CHECK_PIXELS && {raw[47:40],raw[35:28],raw[23:16],raw[11:4]} !== payload(pixels/(GROUPS*LINES*4)+1,(pixels/4)%(GROUPS*LINES)))
   $fatal(1,"RAW8 lane data mismatch at pixel %0d: %h",pixels,raw);
  pixels=pixels+4;
 end
 else if(valid_run!=0)begin
  if(valid_run!=GROUPS)$fatal(1,"RAW8 valid line split: run=%0d expected=%0d",valid_run,GROUPS);
  line_runs=line_runs+1;valid_run=0;
 end
 if(diag[46])begin
  headers=headers+1;
  if(headers<10)$display("HEADER %h vc=%d dt=%h",diag[31:0],diag[44:43],diag[42:37]);
 end
end
initial begin
 repeat(20) @(negedge clk);rst=0;repeat(40) @(negedge clk);
 for(f=1;f<=FRAMES;f=f+1) begin
  start_packet();word(header(8'h00,16'(f)));end_packet();
  for(line=0;line<LINES;line=line+1) begin
   start_packet();word(header(8'h2a,16'(GROUPS*4)));
   for(i=0;i<GROUPS;i=i+1)word(payload(f,line*GROUPS+i));
   word(0);end_packet();
  end
  start_packet();word(header(8'h01,16'(f)));end_packet();
 end
 repeat(100)@(negedge clk);
 $display("Observed frames=%0d pixels=%0d headers=%0d",frames,pixels,headers);
 if(frames!=FRAMES||pixels!=FRAMES*GROUPS*LINES*4||line_runs!=FRAMES*LINES)$fatal(1,"Receiver count/line continuity mismatch (investigate stimulus/alignment)");
 $display("PASS MIPI RAW8 frames=%0d lines=%0d groups_per_line=%0d check_pixels=%0d",FRAMES,line_runs,GROUPS,CHECK_PIXELS);$finish;
end
endmodule
