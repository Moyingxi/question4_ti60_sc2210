`timescale 1ns/1ps
// The receiver's byte alignment buffer outlives the physical HS burst.
// Delay its internal LP gate so final bytes can drain through that buffer.
// Physical D-PHY HS/termination enables must continue using undelayed LP.
// This does not register, reorder or change the edge of the lane data.
module v8_csi_lp_align (
    input clk,
    input rst,
    input lp_p,
    input lp_n,
    output rx_lp_p,
    output rx_lp_n
);
    reg [3:0] lp_p_q = 4'hf;
    reg [3:0] lp_n_q = 4'hf;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lp_p_q <= 4'hf;
            lp_n_q <= 4'hf;
        end else begin
            lp_p_q <= {lp_p_q[2:0],lp_p};
            lp_n_q <= {lp_n_q[2:0],lp_n};
        end
    end
    assign rx_lp_p = lp_p_q[3];
    assign rx_lp_n = lp_n_q[3];
endmodule
