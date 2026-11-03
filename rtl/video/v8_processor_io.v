`timescale 1ns/1ps
// command[25]: exact component path; [24:23]: 0 Sobel,1 prep,2 legacy sweep,3 final.
module v8_processor_io #(parameter WIDTH=1920,HEIGHT=1080,FAST_LABEL_LIMIT=8192)(
    input clk,rst_n,input [25:0] command,input command_valid,output command_ready,
    input [127:0] raw_word,input raw_valid,output raw_ready,
    output [127:0] result_word,output result_valid,input result_ready,
    output done,output reg busy,
    input diag_request,output diag_ack,output [319:0] diag_snapshot,
    input [36:0] wb_config,output [36:0] wb_applied,
    output wb_ack,output [319:0] wb_snapshot
);
    localparam FAST_WORDS=WIDTH*HEIGHT*3/16;
    reg [1:0] phase;
    reg fast;
    reg [3:0] input_index;
    reg [1:0] output_index;
    reg [127:0] packed_word;
    reg packed_valid;
    reg [19:0] fast_word_index,final_index;
    wire launch=command_valid && command_ready;
    wire fast_prep=fast && phase==1;
    wire fast_final=fast && phase==3;
    wire [31:0] front_pixel,hyst_pixel,scaled_pixel;
    wire fv,fr,fl,fb,hv,hr,hl,hb,sv,sl;
    wire accept_pixel=!packed_valid || result_ready;
    wire scale_ce=!sv || accept_pixel;
    wire cc_ready,cc_valid,cc_last,cc_busy,cc_done,cc_overflow;
    wire [37:0] cc_data;
    wire [14:0] cc_labels;
    wire label_valid,label_last,label_ready;
    wire [95:0] label_record;
    wire label_ce=!label_valid || label_ready;
    wire fast_packed_valid;
    wire [127:0] fast_packed_word;
    wire unpack_ready,record_valid,record_ready;
    wire [95:0] final_record;
    wire [3:0] marks;
    reg final_valid,final_last;
    reg [23:0] final_meta;
    wire final_ce=!final_valid || accept_pixel;
    wire [31:0] final_pixel={final_meta[23:8],7'd0,|marks,final_meta[7:0]};
    wire front_ready=fast_prep?cc_ready:phase==1?accept_pixel:(!sv || accept_pixel);
    wire [31:0] input_pixel=raw_word[input_index[1:0]*32+:32];
    wire [31:0] output_pixel=fast_final?final_pixel:phase==1?front_pixel:phase==2?hyst_pixel:scaled_pixel;
    wire output_valid=fast_prep?1'b0:fast_final?final_valid:phase==1?fv:phase==2?hv:sv;
    wire output_last=fast_final?final_last:phase==1?fl:phase==2?hl:sl;
    wire input_accept=phase<2?fr:phase==2?hr:scale_ce && busy;
    assign command_ready=!busy && !packed_valid && !cc_busy && !fast_packed_valid;
    assign raw_ready=fast_final?unpack_ready && busy:input_accept && (phase<2?input_index==15:input_index[1:0]==3);
    assign result_word=fast_prep?fast_packed_word:packed_word;
    assign result_valid=fast_prep?fast_packed_valid:packed_valid;
    wire fast_prep_done=fast_prep && fast_packed_valid && result_ready && fast_word_index==FAST_WORDS-1;
    assign done=fast_prep?fast_prep_done:output_valid && accept_pixel && output_last;
    v8_frontend #(WIDTH,HEIGHT) frontend(
        clk,rst_n,launch && command[24:23]<2,command[23],command[22],
        command[21:11],command[10:0],raw_word[input_index*8+:8],
        raw_valid && busy && phase<2,fr,front_pixel,fv,front_ready,fl,fb,diag_request,diag_ack,diag_snapshot,wb_config,wb_applied,wb_ack,wb_snapshot);
    v8_components #(WIDTH,HEIGHT,14,FAST_LABEL_LIMIT) components(
        clk,rst_n,launch && command[25] && command[24:23]==1,
        front_pixel,fv && fast_prep,cc_ready,cc_data,cc_valid,label_ce,cc_last,
        cc_busy,cc_done,cc_overflow,cc_labels,final_record[79:24],marks,final_ce);
    v8_label_scale #(WIDTH,HEIGHT) label_scale(clk,rst_n,label_ce,cc_valid,cc_data,label_valid,label_record,label_last);
    wire [95:0] stored_record={label_last && cc_overflow,label_record[94:0]};
    v8_gearbox #(96,128) label_pack(clk,rst_n,launch,stored_record,label_valid,label_ready,
                                  fast_packed_word,fast_packed_valid,result_ready && fast_prep);
    v8_gearbox #(128,96) label_unpack(clk,rst_n,launch,raw_word,raw_valid && busy && fast_final,unpack_ready,
                                    final_record,record_valid,record_ready);
    assign record_ready=final_ce && fast_final;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin final_valid<=0;final_last<=0;final_index<=0;end
        else if(launch) begin final_valid<=0;final_last<=0;final_index<=0;end
        else if(final_ce) begin
            final_valid<=record_valid && fast_final;
            if(record_valid && fast_final) begin
                final_meta<=final_record[23:0];final_last<=final_index==WIDTH*HEIGHT/4-1;
                final_index<=final_index+1'b1;
            end
        end
    end
    v8_hysteresis #(WIDTH,HEIGHT) hysteresis(
        clk,rst_n,launch && command[24:23]==2,input_pixel,
        raw_valid && busy && phase==2,hr,hyst_pixel,hv,accept_pixel,hl,hb);
    v8_scale #(WIDTH,HEIGHT) scaler(clk,rst_n,scale_ce,
        phase==0?fv:(phase==3 && !fast && busy && raw_valid),
        phase==0?front_pixel:input_pixel,sv,scaled_pixel,sl);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin phase<=0;fast<=0;input_index<=0;output_index<=0;packed_valid<=0;busy<=0;fast_word_index<=0;end
        else begin
            if(launch) begin phase<=command[24:23];fast<=command[25];busy<=1;input_index<=0;output_index<=0;fast_word_index<=0;end
            if(raw_valid && input_accept && busy && !fast_final) begin
                if(phase<2) input_index<=input_index+1'b1;
                else input_index<={2'b0,input_index[1:0]+2'd1};
            end
            if(packed_valid && result_ready) packed_valid<=0;
            if(output_valid && accept_pixel && busy) begin
                packed_word[output_index*32+:32]<=output_pixel;
                output_index<=output_index+1'b1;
                if(output_index==3) packed_valid<=1;
                if(output_last) busy<=0;
            end
            if(fast_prep && fast_packed_valid && result_ready) begin
                fast_word_index<=fast_word_index+1'b1;
                if(fast_prep_done) busy<=0;
            end
        end
    end
endmodule
