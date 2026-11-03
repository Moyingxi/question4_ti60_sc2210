// 自检仿真：tb_camera_pack；断言失败立即停止，成功打印 PASS。
`timescale 1ns / 1ps
module tb_camera_pack;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst_n = 0, vs = 0, de = 0, ready = 1;
    reg [31:0] pixels;
    wire [145:0] data;
    wire valid;
    wire [31:0] frames, overflows, errors;
    camera_pack dut (
        clk,
        rst_n,
        vs,
        de,
        pixels,
        data,
        valid,
        ready,
        frames,
        overflows,
        errors
    );
    integer f = 0, y, x, i, seen = 0, total = 0, p = 0;
    reg [127:0] expect_word;
    always @(posedge clk)
        if (valid && ready) begin
            if (data[144:128] !== seen[16:0]) $fatal(1, "packet index f=%0d seen=%0d", f, seen);
            for (integer k = 0; k < 16; k = k + 1) expect_word[k*8+:8] = (seen * 16 + k) & 255;
            if (data[127:0] !== expect_word) $fatal(1, "packet pixel order");
            if (data[145] !== ((f == 3) && (seen == 129599))) $fatal(1, "bad frame flag");
            seen  = seen + 1;
            total = total + 1;
        end
    initial begin
        repeat (8) @(negedge clk);
        rst_n = 1;
        for (f = 0; f < 4; f = f + 1) begin
            seen = 0;
            p    = 0;
            vs   = 1;
            repeat (4) @(negedge clk);
            vs = 0;
            for (y = 0; y < 1080; y = y + 1) begin
                for (x = 0; x < ((f == 3 && y == 1079) ? 484 : 480); x = x + 1) begin
                    de = 1;
                    for (i = 0; i < 4; i = i + 1) pixels[i*8+:8] = (p + i) & 255;
                    p     = p + 4;
                    ready = !(f == 1 && y == 10 && x >= 4 && x < 24);
                    @(negedge clk);
                end
                de = 0;
                repeat (12) @(negedge clk);
            end
            if ((f != 1) && (seen != 129600)) $fatal(1, "frame size %0d", seen);
            if (f == 1 && seen >= 129600) $fatal(1, "overflow frame not dropped");
            repeat (20) @(negedge clk);
        end
        if (overflows == 0 || errors != 1) $fatal(1, "fault counters");
        $display("PASS camera pack: full frames, pixel order, FIFO overflow recovery, malformed last line");
        $finish;
    end
endmodule
