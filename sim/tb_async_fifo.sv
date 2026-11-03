// 自检仿真：tb_async_fifo；断言失败立即停止，成功打印 PASS。
`timescale 1ns / 1ps
module tb_async_fifo;
    reg wc = 0, rc = 0;
    always #3.5 wc = ~wc;
    always #5.7 rc = ~rc;
    reg rst = 0, wv = 0, rr = 0;
    wire wr, rv;
    wire [31:0] rd;
    wire [5:0] wl, rl;
    integer sent = 0, got = 0;
    reg accepted = 0;
    reg [31:0] ws = 32'h79312, rs = 32'hb7139;
    wire [31:0] wd = sent ^ 32'h19af3456;
    async_fifo #(32, 5) dut (
        wc,
        rst,
        wd,
        wv,
        wr,
        wl,
        rc,
        rst,
        rd,
        rv,
        rr,
        rl
    );
    always @(negedge wc)
        if (rst) begin
            ws = {ws[30:0], ws[31] ^ ws[21] ^ ws[1] ^ ws[0]};
            if (!wv || accepted) wv = sent < 100000 && ws[1:0] != 0;
        end
    always @(posedge wc)
        if (rst) begin
            accepted = wv && wr;
            if (accepted) sent <= sent + 1;
            if (wl > 32) $fatal(1, "write level");
        end
    reg stalled = 0;
    reg [31:0] held;
    always @(negedge rc)
        if (rst) begin
            rs = {rs[30:0], rs[31] ^ rs[21] ^ rs[1] ^ rs[0]};
            rr = rs[2:0] < 3;
        end
    always @(posedge rc)
        if (rst) begin
            if (stalled && (!rv || rd !== held)) $fatal(1, "FIFO stalled output changed");
            stalled = rv && !rr;
            held    = rd;
            if (rv && rr) begin
                if (rd !== (got ^ 32'h19af3456)) $fatal(1, "FIFO sequence %0d", got);
                got = got + 1;
            end
            if (rl > 33) $fatal(1, "read level");
        end
    initial begin
        #100;
        rst = 1;
        wait (got == 100000);
        #100;
        $display("PASS async FIFO: 100000 words, unrelated clocks, wrap/full/empty/backpressure");
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "FIFO timeout");
    end
endmodule
