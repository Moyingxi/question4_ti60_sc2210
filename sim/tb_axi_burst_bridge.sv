// 自检仿真：tb_axi_burst_bridge；断言失败立即停止，成功打印 PASS。
`timescale 1ns / 1ps
module tb_axi_burst_bridge;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg wr_req = 0, rd_req = 0;
    integer wcmd = 0, rcmd = 0, wbeat = 0, rbeat = 0, wgot = 0, rgot = 0, wfin = 0, rfin = 0;
    // Cover the enlarged display bursts as well as the unchanged 16-beat writes.
    function integer read_beats(input integer cmd);
        case(cmd%5) 0:read_beats=16;1:read_beats=32;2:read_beats=128;
            3:read_beats=240;default:read_beats=256;endcase
    endfunction
    wire [7:0] read_len=read_beats(rcmd)-1;
    reg [31:0] wr_addr = 4096, rd_addr = 0;
    wire wa, ra;
    reg [127:0] wd;
    reg wv = 0;
    wire ww, wdone, we;
    wire [127:0] rd;
    wire rv;
    reg rr = 0;
    wire rdone, re;
    wire [7:0] aid, alen, wid, rid, bid;
    wire [31:0] aa;
    wire [ 2:0] az;
    wire [1:0] ab, al;
    wire av, at;
    reg ar = 0;
    wire [127:0] awd;
    wire [15:0] st;
    wire last, awvalid;
    reg awready = 0;
    reg [127:0] ard;
    reg arlast = 0, arvalid = 0;
    wire arready;
    reg [1:0] rresp = 0, bresp = 0;
    reg  bv = 0;
    wire br;
    assign rid = 0;
    assign bid = 1;
    axi_burst_bridge dut (
        clk,
        rst_n,
        wr_req,
        wr_addr,
        8'd15,
        wa,
        wd,
        wv,
        ww,
        wdone,
        we,
        rd_req,
        rd_addr,
        read_len,
        ra,
        rd,
        rv,
        rr,
        rdone,
        re,
        aid,
        aa,
        alen,
        az,
        ab,
        al,
        av,
        ar,
        at,
        wid,
        awd,
        st,
        last,
        awvalid,
        awready,
        rid,
        ard,
        arlast,
        arvalid,
        arready,
        rresp,
        bid,
        bresp,
        bv,
        br
    );
    integer bdelay = -1, rdelay = -1;
    reg write_active = 0, read_active = 0;
    reg [31:0] rng = 32'h517349da;
    reg prevw = 0;
    integer srcbeat = 0;
    reg [127:0] mem[0:1023];
    integer i;
    function [127:0] pattern(input integer x);
        pattern = {32'h89313a5c, x[31:0], ~x[31:0], 32'h5ac6719e};
    endfunction
    always @(negedge clk)
        if (rst_n) begin
            rng     = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            ar      = rng[0];
            awready = write_active && rng[2:1] != 0;
            rr      = rng[4:3] != 0;
            wr_req  = wcmd < 24;
            rd_req  = rcmd < 24;
            if (!wv || prevw) begin
                wv = wcmd > wfin && srcbeat < 16 && rng[6:5] != 0;
                wd = pattern(wfin * 16 + srcbeat);
            end
            if (bdelay > 0) bdelay = bdelay - 1;
            if (bdelay == 0) begin
                bv     = 1;
                bresp  = wfin == 7 ? 2'b10 : 0;
                bdelay = -1;
            end
            if (rdelay > 0) rdelay = rdelay - 1;
            if (read_active && rdelay == 0 && (!arvalid || arready)) begin
                arvalid = rng[8:7] != 0;
                ard     = pattern(rfin * 256 + rbeat);
                arlast  = rbeat == read_beats(rfin)-1;
                rresp   = (rfin == 9 && rbeat == 6) ? 2'b10 : 0;
            end
        end
    reg ahold = 0;
    reg [40:0] acmd;
    always @(posedge clk)
        if (rst_n) begin
            if (ahold && {at, alen, aa} !== acmd) $fatal(1, "address changed under backpressure");
            ahold = av && !ar;
            acmd  = {at, alen, aa};
            if (wa) begin
                wcmd = wcmd + 1;
                wr_addr <= wr_addr + 256;
            end
            if (ra) begin
                rcmd = rcmd + 1;
                rd_addr <= rd_addr + 4096;
            end
            if (av && ar) begin
                if (alen != (at?15:read_beats(rfin)-1) || az != 4 || ab != 1) $fatal(1, "command metadata");
                if (at) begin
                    write_active = 1;
                    wbeat        = 0;
                end
                else begin
                    read_active = 1;
                    rbeat       = 0;
                    rdelay      = 110;
                end
            end
            prevw = wv && ww;
            if (prevw) srcbeat = srcbeat + 1;
            if (awvalid && awready) begin
                if (awd !== pattern(wfin * 16 + wbeat) || last !== (wbeat == 15)) $fatal(1, "write beat");
                wbeat = wbeat + 1;
                wgot  = wgot + 1;
                if (wbeat == 16) begin
                    write_active = 0;
                    bdelay       = 8;
                end
            end
            if (bv && br) bv <= 0;
            if (arvalid && arready) begin
                if (rd !== pattern(rfin * 256 + rbeat)) $fatal(1, "read data");
                rbeat = rbeat + 1;
                rgot  = rgot + 1;
                if (arlast) begin
                    read_active = 0;
                    arvalid <= 0;
                end
            end
            if (wdone) begin
                if (we !== (wfin == 7)) $fatal(1, "B error propagation");
                wfin    = wfin + 1;
                srcbeat = 0;
                wv <= 0;
            end
            if (rdone) begin
                if (re !== (rfin == 9)) $fatal(1, "R error propagation");
                rfin = rfin + 1;
            end
        end
    initial begin
        repeat (8) @(negedge clk);
        rst_n = 1;
        wait (wfin == 24 && rfin == 24);
        #100;
        if (wgot != 384 || rgot != 3104) $fatal(1, "beat count %0d/%0d",wgot,rgot);
        $display("PASS AXI bridge: 16/32/128/240/256-beat reads, independent writes, random stalls, long latency, B/R errors");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "AXI timeout w=%0d r=%0d", wfin, rfin);
    end
endmodule
