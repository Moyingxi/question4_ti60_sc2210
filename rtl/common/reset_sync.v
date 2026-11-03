`timescale 1ns / 1ps

// ============================================================================
// 复位同步器：异步拉低复位，经过三级寄存器在目标时钟域同步释放。
// ============================================================================
module reset_sync (
    input  clk,                                                             // 输入：本模块工作时钟
    input  arst_n,                                                          // 输入：外部异步低有效复位
    output rst_n                                                            // 输出：低有效复位
);
    (* async_reg = "true" *) reg [2:0] sync = 0;                            // 内部 reg：三级复位释放移位寄存器

    always @(posedge clk or negedge arst_n)
        if (!arst_n) sync <= 0;
        else sync <= {sync[1:0], 1'b1};

    assign rst_n = sync[2];
endmodule
