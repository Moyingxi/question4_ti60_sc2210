`timescale 1ns/1ps
// 历史录制、冻结、回放和A/B比较。所有显示地址只在帧边界采用。
// 比较期间历史范围不变；A/B使用从最旧有效帧起的索引，前后选择饱和。
module v8_playback_control #(parameter HISTORY_FRAMES=232)(
    input clk,rst_n,freeze_press,replay_press,compare_press,select_press,prev_press,next_press,
    input frame_boundary,display_available,result_start,result_finish,result_success,
    output record_frame,output [8:0] record_slot,output reg record_busy,
    output reg [8:0] history_count,output reg [1:0] mode,
    output view_history,hold_live,view_compare,output [8:0] view_slot,view_slot_b,
    output [8:0] replay_remaining,output replay_waiting,
    output reg selected_b,output reg [8:0] index_a,index_b
);
    localparam LIVE=0,FROZEN=1,REPLAY=2,PAUSED=3;
    reg [8:0] head,tail,play_slot,remaining;
    reg [1:0] requested;
    reg freeze_pending,comparing;
    reg [1:0] target,nmode,nrequested;
    reg ncompare;
    reg [8:0] nslot,nremaining;
    function [8:0] advance(input [8:0] s);
        advance=s==HISTORY_FRAMES-1?9'd0:s+9'd1;
    endfunction
    function [8:0] slot_at(input [8:0] index);
        reg [9:0] sum;
        begin sum={1'b0,head}+index;slot_at=sum>=HISTORY_FRAMES?sum-HISTORY_FRAMES:sum;end
    endfunction
    wire toggle_freeze=freeze_pending ^ freeze_press;
    always @* begin
        target=requested;
        if(replay_press) target=requested==1?0:1;
        if(compare_press) target=requested==2?0:2;
        nmode=mode;ncompare=comparing;nslot=play_slot;nremaining=remaining;nrequested=target;
        if(frame_boundary) begin
            if(target==0) begin
                if(mode[1] || comparing) begin nmode=LIVE;ncompare=0;nremaining=0;end
                else if(toggle_freeze && !replay_press && !compare_press)
                    if(mode==FROZEN) nmode=LIVE;else if(display_available) nmode=FROZEN;
            end else if(!record_busy) begin
                if(history_count==0) begin nrequested=0;nmode=LIVE;ncompare=0;end
                else if(target==2) begin nmode=PAUSED;ncompare=1;end
                else if(!mode[1] || comparing) begin
                    nmode=REPLAY;ncompare=0;nslot=head;nremaining=history_count-1'b1;
                end else if(toggle_freeze) nmode=mode==PAUSED?REPLAY:PAUSED;
                else if(mode==REPLAY) begin
                    if(remaining!=0) begin nslot=advance(play_slot);nremaining=remaining-1'b1;end
                    else begin nmode=LIVE;nrequested=0;end
                end
            end
        end
    end
    assign record_frame=target==0 && !mode[1] && !comparing && !record_busy;
    assign record_slot=tail;
    assign view_history=nmode[1];
    assign view_compare=ncompare;
    assign hold_live=nmode==FROZEN;
    assign view_slot=ncompare?slot_at(comparing?index_a:9'd0):nslot;
    assign view_slot_b=slot_at(comparing?index_b:history_count-1'b1);
    assign replay_remaining=remaining;
    assign replay_waiting=requested!=0 && !mode[1];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            head<=0;tail<=0;history_count<=0;record_busy<=0;mode<=LIVE;
            requested<=0;freeze_pending<=0;comparing<=0;play_slot<=0;remaining<=0;
            selected_b<=0;index_a<=0;index_b<=0;
        end else begin
            requested<=nrequested;freeze_pending<=toggle_freeze;
            if(frame_boundary) begin
                mode<=nmode;comparing<=ncompare;play_slot<=nslot;remaining<=nremaining;freeze_pending<=0;
                if(ncompare && !comparing) begin index_a<=0;index_b<=history_count-1'b1;selected_b<=0;end
            end
            if(comparing && requested==2) begin
                if(select_press) selected_b<=!selected_b;
                if(prev_press != next_press) begin
                    if(selected_b) begin
                        if(prev_press && index_b!=0) index_b<=index_b-1'b1;
                        if(next_press && index_b+1<history_count) index_b<=index_b+1'b1;
                    end else begin
                        if(prev_press && index_a!=0) index_a<=index_a-1'b1;
                        if(next_press && index_a+1<history_count) index_a<=index_a+1'b1;
                    end
                end
            end
            if(result_start && record_frame) begin
                record_busy<=1;
                if(history_count==HISTORY_FRAMES) begin head<=advance(head);history_count<=history_count-1'b1;end
            end
            if(result_finish && record_busy) begin
                record_busy<=0;
                if(result_success) begin tail<=advance(tail);history_count<=history_count+1'b1;end
            end
        end
    end
endmodule
