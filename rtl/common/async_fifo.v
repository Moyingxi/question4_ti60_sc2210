`timescale 1ns / 1ps

// ============================================================================
// 异步 FIFO：双口块 RAM、格雷码指针跨时钟域同步及读侧预取。
// 写侧须遵守 valid/ready；读侧预取寄存器在反压期间保持数据不变。
// ============================================================================
module async_fifo #(
    parameter WIDTH = 128,
    parameter ADDR  = 8
) (
    input              wclk,                                                // 输入：写侧时钟
    input              wrst_n,                                              // 输入：写侧低有效复位
    input  [WIDTH-1:0] wdata,                                               // 输入：待写入数据
    input              wvalid,                                              // 输入：写数据有效
    output             wready,                                              // 输出：写侧非满可接收
    output [   ADDR:0] wlevel,                                              // 输出：写域估计的 RAM 已用深度
    input              rclk,                                                // 输入：读侧时钟
    input              rrst_n,                                              // 输入：读侧低有效复位
    output [WIDTH-1:0] rdata,                                               // 输出：预取输出数据
    output             rvalid,                                              // 输出：预取输出有效
    input              rready,                                              // 输入：下游接收就绪
    output [   ADDR:0] rlevel                                               // 输出：读域已用深度，含预取寄存器
);
    localparam DEPTH = 1 << ADDR;
    (* ram_style="block" *) reg [WIDTH-1:0] mem[0:DEPTH-1];                 // 内部 reg：双时钟 FIFO 数据 RAM
    reg [ADDR:0] wb = 0;                                                    // 内部 reg：写二进制指针
    reg [ADDR:0] wg = 0;                                                    // 内部 reg：写格雷码指针
    reg [ADDR:0] rb = 0;                                                    // 内部 reg：读二进制指针
    reg [ADDR:0] rg = 0;                                                    // 内部 reg：读格雷码指针
    (* async_reg="true" *) reg [ADDR:0] rq1 = 0;                            // 内部 reg：读格雷码指针在写域的两级同步
    (* async_reg="true" *) reg [ADDR:0] rq2 = 0;                            // 内部 reg：读格雷码指针在写域的两级同步
    (* async_reg="true" *) reg [ADDR:0] wq1 = 0;                            // 内部 reg：写格雷码指针在读域的两级同步
    (* async_reg="true" *) reg [ADDR:0] wq2 = 0;                            // 内部 reg：写格雷码指针在读域的两级同步
    reg full = 0;                                                           // 内部 reg：下一周期写满标志
    reg [WIDTH-1:0] out_data;                                               // 内部 reg：读预取数据寄存器
    reg out_valid = 0;                                                      // 内部 reg：读预取寄存器有效
    function [ADDR:0] ungray(input [ADDR:0] g);
        integer k;
        begin
            ungray[ADDR] = g[ADDR];
            for (k = ADDR - 1; k >= 0; k = k - 1) ungray[k] = ungray[k+1] ^ g[k];
        end
    endfunction
    wire          push = wvalid && !full;                                   // 内部 wire：本周期写入握手
    wire [ADDR:0] wn = wb + push;                                           // 内部 wire：下一写二进制指针
    wire [ADDR:0] wgn = (wn >> 1) ^ wn;                                     // 内部 wire：下一写格雷码指针
    wire          empty = (rg == wq2);                                      // 内部 wire：RAM 读空标志，不含预取寄存器
    wire          fetch = (!out_valid || rready) && !empty;                 // 内部 wire：从 RAM 预取一字使能
    wire [ADDR:0] rn = rb + fetch;                                          // 内部 wire：下一读二进制指针

    assign wready = !full;
    assign wlevel = wb - ungray(rq2);
    assign rlevel = ungray(wq2) - rb + out_valid;
    assign rdata  = out_data;
    assign rvalid = out_valid;

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wb   <= 0;
            wg   <= 0;
            full <= 0;
            rq1  <= 0;
            rq2  <= 0;
        end
        else begin
            rq1  <= rg;
            rq2  <= rq1;
            wb   <= wn;
            wg   <= wgn;
            full <= (wgn == {~rq2[ADDR:ADDR-1], rq2[ADDR-2:0]});
        end
    end

    always @(posedge wclk) if (push) mem[wb[ADDR-1:0]] <= wdata;

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rb        <= 0;
            rg        <= 0;
            wq1       <= 0;
            wq2       <= 0;
            out_valid <= 0;
        end
        else begin
            wq1 <= wg;
            wq2 <= wq1;
            rb  <= rn;
            rg  <= (rn >> 1) ^ rn;
            if (fetch) out_valid <= 1;

            else if (rready) out_valid <= 0;
        end
    end

    always @(posedge rclk) if (fetch) out_data <= mem[rb[ADDR-1:0]];
endmodule
