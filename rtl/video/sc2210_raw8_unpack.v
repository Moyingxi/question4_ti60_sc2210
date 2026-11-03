`timescale 1ns/1ps
// csi_rx DAT: earliest pixel is [11:4], then [23:16], [35:28], [47:40].
// camera_pack consumes the LOW byte first. The reference demo instead reverses
// its input word because W0_FIFO_32/R0_FIFO_8 use big-endian width conversion.
// Do NOT copy that reversal into our little-endian packet stream.
module sc2210_raw8_unpack(input [47:0] raw,output [31:0] pixels);
    assign pixels={raw[47:40],raw[35:28],raw[23:16],raw[11:4]};
endmodule
