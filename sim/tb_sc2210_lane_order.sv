`timescale 1ns/1ps
// Reference demo's *actual* unmodified big-endian 32->128->8 FIFO chain.
// Checks the boundary missed by tests that inject already-ordered RAW bytes.
module tb_sc2210_lane_order;
    parameter OLD_ORDER=0;
    reg wc=0,dc=0,pc=0,reset=1;
    always #11 wc=~wc;
    always #5.208333 dc=~dc;
    always #3.367003 pc=~pc;
    reg [47:0] raw=0;reg wen=0;
    wire [31:0] actual;
    sc2210_raw8_unpack dut(raw,actual);
    wire [31:0] tested=OLD_ORDER?{raw[11:4],raw[23:16],raw[35:28],raw[47:40]}:actual;
    wire [63:0] demo_rx={2{raw[47:40],raw[35:28],raw[23:16],raw[11:4]}};
    wire [63:0] demo_frame={demo_rx[7:0],demo_rx[15:8],demo_rx[23:16],demo_rx[31:24],
                           demo_rx[39:32],demo_rx[47:40],demo_rx[55:48],demo_rx[63:56]};
    wire [127:0] wide;wire wfempty,rffull,rfempty;wire [7:0] reference_pixel;
    wire bridge=!wfempty&&!rffull;
    W0_FIFO_32 wf(.a_rst_i(reset),.wr_clk_i(wc),.wr_en_i(wen),.wdata(demo_frame[31:0]),
                 .rd_clk_i(dc),.rd_en_i(bridge),.rdata(wide),.empty_o(wfempty));
    R0_FIFO_8 rf(.a_rst_i(reset),.wr_clk_i(dc),.wr_en_i(bridge),.wdata(wide),
                .full_o(rffull),.rd_clk_i(pc),.rd_en_i(!rfempty),.rdata(reference_pixel),.empty_o(rfempty));
    reg [7:0] expected[0:255],from_v8[0:255];
    integer sent=0,received=0,group,p;
    function [7:0] pixel(input integer i);pixel=(i*7+11)&255;endfunction
    always @(posedge pc) if(!reset && !rfempty) begin
        if(reference_pixel!==expected[received]) $fatal(1,"demo FIFO ordering pixel%0d got%h expected%h",received,reference_pixel,expected[received]);
        if(reference_pixel!==from_v8[received]) $fatal(1,"V8 MIPI lane ordering differs from reference at pixel%0d",received);
        received=received+1;
    end
    initial begin
        for(p=0;p<256;p=p+1)expected[p]=pixel(p);
        repeat(30) @(negedge wc);reset=0;
        repeat(50) @(negedge wc);
        for(group=0;group<64;group=group+1) begin
            for(p=0;p<4;p=p+1) raw[p*12+:12]={pixel(group*4+p),4'h5};
            #0.1;
            for(p=0;p<4;p=p+1) from_v8[group*4+p]=tested[p*8+:8];
            wen=1;@(negedge wc);wen=0;
            repeat(5) @(negedge wc);
        end
        wait(received==256);repeat(30) @(negedge wc);
        $display("PASS SC2210 MIPI lane order: 256 pixels match unmodified demo big-endian FIFOs");$finish;
    end
    initial begin #1000000;$fatal(1,"lane order timeout %0d",received);end
endmodule
