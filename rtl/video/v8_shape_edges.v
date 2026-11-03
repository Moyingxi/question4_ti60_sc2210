`timescale 1ns/1ps
// Detect contrast BEFORE reduction: full-resolution horizontal/vertical edges
// are max-pooled over each 2x2 cell. Thin outlines cannot fall between samples.
// A two-pixel baseline preserves contrast spread by camera/display blur.
// Three RAM10s: two grayscale rows and pooled row accumulation.
module v8_shape_edges #(parameter W=960,H=540)(
    input clk,rst_n,frame_start,sample_valid,
    input [7:0] gray,input [1:0] sensitivity,input [9:0] x,y,
    output reg valid,output reg edge_pixel
);
    (* ram_style="block" *) reg [7:0] line[0:2047];
    (* ram_style="block" *) reg pool_line[0:511];
    reg [7:0] left,left2,gray_q,left_q,upper_q;
    reg pixel_valid_q,edge_valid_q,edge_q;
    reg [9:0] xq,yq,xe,ye;
    reg horizontal_pool,group_valid,group_valid_q,group_hit,group_hit_q,pool_q;
    reg [8:0] group_x,group_xq;
    reg group_y,group_yq;
    reg group_final,group_final_q;
    reg [19:0] input_count;
    wire [7:0] dx=gray_q>left_q?gray_q-left_q:left_q-gray_q;
    wire [7:0] dy=gray_q>upper_q?gray_q-upper_q:upper_q-gray_q;
    wire [7:0] contrast_limit=8'd32-{sensitivity,3'b000};
    wire four_pixels=(xe[0]==0?1'b0:horizontal_pool)|edge_q;
    wire four_rows=group_yq==0?group_hit_q:pool_q|group_hit_q;
    always @(posedge clk) begin
        if(sample_valid) begin upper_q<=line[{y[0],x}];line[{y[0],x}]<=gray;end
        if(group_valid)pool_q<=pool_line[group_x];
        if(group_valid_q)pool_line[group_xq]<=four_rows;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            left<=0;left2<=0;gray_q<=0;left_q<=0;pixel_valid_q<=0;edge_valid_q<=0;edge_q<=0;
            xq<=0;yq<=0;xe<=0;ye<=0;horizontal_pool<=0;group_valid<=0;group_valid_q<=0;
            group_hit<=0;group_hit_q<=0;group_x<=0;group_xq<=0;group_y<=0;group_yq<=0;
            valid<=0;edge_pixel<=0;group_final<=0;group_final_q<=0;input_count<=0;
        end else begin
            if(frame_start)input_count<=sample_valid?20'd1:20'd0;
            else if(sample_valid)input_count<=input_count+1'b1;
            pixel_valid_q<=sample_valid;
            if(sample_valid)begin gray_q<=gray;left_q<=x<2?gray:left2;left2<=left;left<=gray;xq<=x;yq<=y;end
            edge_valid_q<=pixel_valid_q;xe<=xq;ye<=yq;
            edge_q<=(xq>=2 && dx>=contrast_limit)||(yq>=2 && dy>=contrast_limit);
            group_valid<=0;
            if(frame_start)horizontal_pool<=0;
            if(edge_valid_q)begin
                if(xe[0]==1)begin
                    group_valid<=1;group_hit<=four_pixels;group_x<=xe[9:1];group_y<=ye[0];horizontal_pool<=0;
                    group_final<=xe==W-1 && ye==H-1;
                end else horizontal_pool<=four_pixels;
            end
            group_valid_q<=group_valid;
            if(group_valid)begin group_hit_q<=group_hit;group_xq<=group_x;group_yq<=group_y;group_final_q<=group_final;end
            // Withhold the last mask bit after any missing input pixel. The
            // detector's exact sample-count check then invalidates the frame.
            valid<=group_valid_q && group_yq==1 && (!group_final_q || input_count==W*H);
            if(group_valid_q && group_yq==1)edge_pixel<=four_rows;
        end
    end
endmodule
