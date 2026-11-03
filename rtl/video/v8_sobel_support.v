`timescale 1ns/1ps
// Reuse the frontend's 3x3 gradient window (11 magnitude + 2 direction +
// 24 untouched metadata bits). A contour needs thresholded, non-perpendicular
// support on both tangent sides. Three-pixel cones tolerate quantized slopes
// and corners; no extra line/frame memory or iteration is introduced.
module v8_sobel_support(
    input [332:0] taps,
    input [10:0] threshold,
    output reg supported
);
    wire [1:0] direction=taps[4*37+11+:2];
    wire [8:0] good;
    genvar i;
    generate for(i=0;i<9;i=i+1) begin:neighbor
        assign good[i]=(taps[i*37+:11]>threshold) &&
                      ((taps[i*37+11+:2]^direction)!=2'b10);
    end endgenerate
    always @* begin
        case(direction)
            0:supported=(|good[2:0]) && (|good[8:6]);
            1:supported=(good[1]|good[2]|good[5]) && (good[3]|good[6]|good[7]);
            2:supported=(good[0]|good[3]|good[6]) && (good[2]|good[5]|good[8]);
            3:supported=(good[0]|good[1]|good[3]) && (good[5]|good[7]|good[8]);
        endcase
    end
endmodule
