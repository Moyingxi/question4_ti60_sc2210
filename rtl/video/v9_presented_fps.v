`timescale 1ns/1ps
// Pixel-domain count of complete LEFT presentations with a different source ID.
// No asynchronous multi-bit counter sampling; IDs travel in the display FIFO.
module v9_presented_fps #(
    parameter CLK_HZ=148500000
)(
    input clk,rst_n,
    input frame_begin,frame_end,pixel_missing,
    input [27:0] source_tag,
    output reg [11:0] fps_bcd,
    output reg [31:0] presented_frames
);
    localparam TIMER_BITS=CLK_HZ>1?$clog2(CLK_HZ):1;
    reg [TIMER_BITS-1:0] ticks;
    reg [11:0] window_bcd;
    reg active,bad,seen;
    reg [27:0] candidate,last_tag;
    wire new_presentation=frame_end && active && !bad && !pixel_missing &&
                          (!seen || candidate!=last_tag);
    function [11:0] increment_bcd(input [11:0] b);
        begin
            if(b==12'h999) increment_bcd=b;
            else if(b[3:0]!=9) increment_bcd=b+12'h001;
            else if(b[7:4]!=9) increment_bcd={b[11:8],b[7:4]+4'd1,4'd0};
            else increment_bcd={b[11:8]+4'd1,8'd0};
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ticks<=0;window_bcd<=0;fps_bcd<=0;presented_frames<=0;
            active<=0;bad<=0;seen<=0;candidate<=0;last_tag<=0;
        end else begin
            if(frame_begin) begin active<=1;bad<=pixel_missing;candidate<=source_tag;end
            else if(active && pixel_missing) bad<=1;
            if(frame_end) active<=0;
            if(new_presentation) begin
                seen<=1;last_tag<=candidate;presented_frames<=presented_frames+1'b1;
            end
            // The closing clock belongs to the ending one-second window.
            if(ticks==CLK_HZ-1) begin
                ticks<=0;fps_bcd<=new_presentation?increment_bcd(window_bcd):window_bcd;
                window_bcd<=0;
            end else begin
                ticks<=ticks+1'b1;
                if(new_presentation) window_bcd<=increment_bcd(window_bcd);
            end
        end
    end
endmodule
