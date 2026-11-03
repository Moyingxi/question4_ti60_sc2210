`timescale 1ns/1ps
// Optional HDMI test source after normal display generation. DDR traffic and
// underrun detection continue normally. All video/control outputs delay equally.
// Mode 0: camera; 1: eight RGB bars; 2: sixteen neutral gray levels.
module v8_diagnostic_display #(
    parameter WIDTH=1920
)(
    input clk,rst_n,input [1:0] mode,
    input [23:0] s_rgb,input s_de,s_hs,s_vs,
    output reg [23:0] m_rgb,output reg m_de,m_hs,m_vs,
    output reg [1:0] active_mode
);
    reg [11:0] x;
    reg vs_q;
    reg [23:0] pattern;
    reg [7:0] gray;
    integer i;
    always @* begin
        pattern=0;gray=0;
        if(x<WIDTH/8) pattern=24'hffffff;
        else if(x<2*WIDTH/8) pattern=24'hffff00;
        else if(x<3*WIDTH/8) pattern=24'h00ffff;
        else if(x<4*WIDTH/8) pattern=24'h00ff00;
        else if(x<5*WIDTH/8) pattern=24'hff00ff;
        else if(x<6*WIDTH/8) pattern=24'hff0000;
        else if(x<7*WIDTH/8) pattern=24'h0000ff;
        for(i=0;i<16;i=i+1)
            if(x>=i*WIDTH/16 && x<(i+1)*WIDTH/16) gray=i*17;
        if(active_mode==2) pattern={gray,gray,gray};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x<=0;vs_q<=0;active_mode<=0;m_rgb<=0;m_de<=0;m_hs<=0;m_vs<=0;
        end else begin
            vs_q<=s_vs;
            if(s_vs && !vs_q) active_mode<=mode==3?2'd0:mode;
            if(s_de) x<=x+1'b1;else x<=0;
            m_de<=s_de;m_hs<=s_hs;m_vs<=s_vs;
            m_rgb<=s_de?(active_mode==0?s_rgb:pattern):24'd0;
        end
    end
endmodule
