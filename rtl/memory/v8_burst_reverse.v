`timescale 1ns/1ps
// Reverse one 16-beat, 128-bit burst, including its four 32-bit pixel lanes.
// AXI stays ascending INCR; the algorithm can scan a frame bottom-right first.
module v8_burst_reverse(
    input clk,rst_n,input [127:0] s_data,input s_valid,output s_ready,
    output [127:0] m_data,output m_valid,input m_ready,output empty
);
    (* ram_style="block" *) reg [127:0] mem[0:15];
    reg [3:0] write_index;
    reg draining,valid_q;
    reg [4:0] remaining;
    reg [127:0] data_q;
    wire fetch=draining && remaining!=0 && (!valid_q || m_ready);
    assign s_ready=!draining;
    assign m_valid=valid_q;
    assign m_data={data_q[31:0],data_q[63:32],data_q[95:64],data_q[127:96]};
    assign empty=!draining && write_index==0;
    always @(posedge clk) begin
        if(s_valid && s_ready) mem[write_index]<=s_data;
        if(fetch) data_q<=mem[remaining[3:0]-4'd1];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin write_index<=0;draining<=0;valid_q<=0;remaining<=0;end
        else begin
            if(s_valid && s_ready) begin
                write_index<=write_index+1'b1;
                if(write_index==15) begin draining<=1;remaining<=16;end
            end
            if(fetch) begin remaining<=remaining-1'b1;valid_q<=1;end
            else if(m_ready) valid_q<=0;
            if(draining && remaining==0 && valid_q && m_ready) draining<=0;
        end
    end
endmodule
