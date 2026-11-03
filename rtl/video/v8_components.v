`timescale 1ns/1ps
// Exact streaming 8-connected components. Union-by-rank; no iteration cap.
// Exhausted labels set overflow, causing the system to replay the held RAW
// frame through the original complete hysteresis path. No truncated result.
module v8_components #(parameter WIDTH=1920, HEIGHT=1080, LABEL_BITS=14, LABEL_LIMIT=(1<<LABEL_BITS))(
    input clk,rst_n,start,
    input [31:0] s_data,input s_valid,output s_ready,
    output [LABEL_BITS+23:0] m_data,output m_valid,input m_ready,
    output m_last,output reg busy,output reg done,output reg overflow,
    output [LABEL_BITS:0] labels_used,
    input [4*LABEL_BITS-1:0] query_labels,output [3:0] query_marks,input query_ce
);
    localparam COUNT=LABEL_LIMIT;
    localparam RUN=0, NEXT=1, A_REQ=2,A_WAIT=3,B_REQ=4,B_WAIT=5,LINK=6,RANK=7,
        F_REQ=8,F_WAIT=9,F_ROOT_REQ=10,F_ROOT_WAIT=11,F_WRITE=12,
        M_REQ=13,M_WAIT=14,M_FLAG_REQ=15,M_FLAG_WAIT=16,IDLE=17;
    reg [4:0] state;
    reg [11:0] x,y,xq,yq;
    reg vq;
    reg [31:0] dataq;
    reg [LABEL_BITS-1:0] left_label,north_q,ne_q,nw_q;
    (* ram_style="block" *) reg [LABEL_BITS-1:0] line_n[0:WIDTH-1],line_ne[0:WIDTH-1];
    (* ram_style="block" *) reg [LABEL_BITS+3:0] parent[0:COUNT-1];
    (* ram_style="block" *) reg seed[0:COUNT-1],root_seed[0:COUNT-1];
    (* ram_style="block" *) reg mark0[0:COUNT-1],mark1[0:COUNT-1],mark2[0:COUNT-1],mark3[0:COUNT-1];
    reg [3:0] marks_q;
    reg [4*LABEL_BITS-1:0] query_q;
    assign query_marks={query_q[3*LABEL_BITS+:LABEL_BITS]!=0 && marks_q[3],
                        query_q[2*LABEL_BITS+:LABEL_BITS]!=0 && marks_q[2],
                        query_q[LABEL_BITS+:LABEL_BITS]!=0 && marks_q[1],
                        query_q[0+:LABEL_BITS]!=0 && marks_q[0]};
    always @(posedge clk) if(query_ce) begin
        query_q<=query_labels;
        marks_q[0]<=mark0[query_labels[0+:LABEL_BITS]];
        marks_q[1]<=mark1[query_labels[LABEL_BITS+:LABEL_BITS]];
        marks_q[2]<=mark2[query_labels[2*LABEL_BITS+:LABEL_BITS]];
        marks_q[3]<=mark3[query_labels[3*LABEL_BITS+:LABEL_BITS]];
    end
    reg [LABEL_BITS:0] next_label;
    assign labels_used=next_label-1'b1;
    wire candidate=dataq[24] || dataq[25];
    wire [LABEL_BITS-1:0] n0=xq==0?0:left_label;
    wire [LABEL_BITS-1:0] n1=(yq==0 || xq==0)?0:nw_q;
    wire [LABEL_BITS-1:0] n2=yq==0?0:north_q;
    wire [LABEL_BITS-1:0] n3=(yq==0 || xq==WIDTH-1)?0:ne_q;
    wire [LABEL_BITS-1:0] first=n0!=0?n0:n1!=0?n1:n2!=0?n2:n3;
    // An exact zero-aware equality test, evaluated in parallel. Avoid the
    // priority-select -> equality chain on RAM-to-ready/clock-enable paths.
    // Chosen label priority, unions, cycles and backpressure semantics unchanged.
    wire different=(n0!=0 && n1!=0 && n0!=n1)||
                   (n0!=0 && n2!=0 && n0!=n2)||
                   (n0!=0 && n3!=0 && n0!=n3)||
                   (n1!=0 && n2!=0 && n1!=n2)||
                   (n1!=0 && n3!=0 && n1!=n3)||
                   (n2!=0 && n3!=0 && n2!=n3);
    reg merged;
    reg [LABEL_BITS-1:0] merged_label;
    wire needs_merge=vq && candidate && different && !merged && !overflow;
    wire fresh=candidate && first==0 && !overflow;
    wire exhausted=next_label==LABEL_LIMIT;
    wire [LABEL_BITS-1:0] chosen=(!candidate || overflow || (fresh && exhausted))?0:
                       merged?merged_label:fresh?next_label[LABEL_BITS-1:0]:first;
    assign m_valid=busy && state==RUN && vq && !needs_merge;
    assign m_data={chosen,dataq[23:0]};
    assign m_last=xq==WIDTH-1 && yq==HEIGHT-1;
    wire emit=m_valid && m_ready;
    assign s_ready=busy && state==RUN && !needs_merge && (!vq || m_ready) && !(vq && m_last);
    wire take=s_valid && s_ready;
    always @(posedge clk) begin
        if(take) begin north_q<=line_n[x];ne_q<=line_ne[x==WIDTH-1?0:x+1'b1];end
        if(emit) begin line_n[xq]<=chosen;line_ne[xq]<=chosen;end
    end
    reg [LABEL_BITS-1:0] neighbors[0:3];
    reg [2:0] ni;
    reg [LABEL_BITS-1:0] acc,walk,ra,rb,winner,loser,flat,flat_root;
    reg [3:0] rank_a,rank_b,new_rank;
    reg rank_update,flat_seed;
    wire [LABEL_BITS-1:0] paddr=(state==F_REQ || state==F_WAIT || state==M_REQ || state==M_WAIT)?flat:walk;
    reg [LABEL_BITS+3:0] parent_q;
    reg seed_q,root_q;
    reg parent_we,root_we;
    reg [LABEL_BITS-1:0] parent_wa,root_wa;
    reg [LABEL_BITS+3:0] parent_wd;
    reg root_wd;
    always @* begin
        parent_we=0;parent_wa=0;parent_wd=0;
        if(emit && fresh && !exhausted) begin parent_we=1;parent_wa=next_label[LABEL_BITS-1:0];parent_wd={4'd0,next_label[LABEL_BITS-1:0]};end
        else if(state==LINK) begin parent_we=1;parent_wa=loser;parent_wd={4'd0,winner};end
        else if(state==RANK && rank_update) begin parent_we=1;parent_wa=winner;parent_wd={new_rank,winner};end
        else if(state==F_WRITE) begin parent_we=1;parent_wa=flat;parent_wd={4'd0,flat_root};end
        root_we=0;root_wa=0;root_wd=0;
        if(emit && fresh && !exhausted) begin root_we=1;root_wa=next_label[LABEL_BITS-1:0];root_wd=0;end
        else if(state==F_WRITE && flat_seed) begin root_we=1;root_wa=flat_root;root_wd=1;end
    end
    wire seed_we=emit && chosen!=0 && (fresh || dataq[25]);
    wire seed_wd=dataq[25];
    always @(posedge clk) begin
        parent_q<=parent[paddr];seed_q<=seed[paddr];root_q<=root_seed[flat_root];
        if(parent_we) parent[parent_wa]<=parent_wd;
        if(seed_we) seed[chosen]<=seed_wd;
        if(root_we) root_seed[root_wa]<=root_wd;
        if(state==M_FLAG_WAIT) begin
            mark0[flat]<=root_q;mark1[flat]<=root_q;mark2[flat]<=root_q;mark3[flat]<=root_q;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;busy<=0;done<=0;overflow<=0;vq<=0;x<=0;y<=0;xq<=0;yq<=0;
            next_label<=1;merged<=0;left_label<=0;nw_q<=0;
        end else begin
            done<=0;
            if(start && !busy) begin
                state<=RUN;busy<=1;overflow<=0;vq<=0;x<=0;y<=0;next_label<=1;merged<=0;left_label<=0;nw_q<=0;
            end
            if(take) begin
                vq<=1;dataq<=s_data;xq<=x;yq<=y;
                if(x==WIDTH-1) begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
            end else if(emit) vq<=0;
            if(emit) begin
                merged<=0;left_label<=chosen;nw_q<=north_q;
                if(fresh) begin
                    if(exhausted) overflow<=1;
                    else next_label<=next_label+1'b1;
                end
                if(m_last) begin
                    flat<=1;
                    if(overflow || (fresh && exhausted) || next_label==1 && !fresh) begin state<=IDLE;busy<=0;done<=1;end
                    else state<=F_REQ;
                end
            end
            case(state)
                RUN: if(needs_merge) begin
                    neighbors[0]<=n0;neighbors[1]<=n1;neighbors[2]<=n2;neighbors[3]<=n3;
                    ni<=0;acc<=0;state<=NEXT;
                end
                NEXT: begin
                    if(ni==4) begin merged<=1;merged_label<=acc;state<=RUN;end
                    else if(neighbors[ni]==0 || neighbors[ni]==acc) ni<=ni+1'b1;
                    else if(acc==0) begin acc<=neighbors[ni];ni<=ni+1'b1;end
                    else begin walk<=acc;state<=A_REQ;end
                end
                A_REQ: state<=A_WAIT;
                A_WAIT: if(parent_q[LABEL_BITS-1:0]!=walk) begin walk<=parent_q[LABEL_BITS-1:0];state<=A_REQ;end
                        else begin ra<=walk;rank_a<=parent_q[LABEL_BITS+:4];walk<=neighbors[ni];state<=B_REQ;end
                B_REQ: state<=B_WAIT;
                B_WAIT: if(parent_q[LABEL_BITS-1:0]!=walk) begin walk<=parent_q[LABEL_BITS-1:0];state<=B_REQ;end
                        else if(walk==ra) begin acc<=ra;ni<=ni+1'b1;state<=NEXT;end
                        else begin
                            rb<=walk;rank_b<=parent_q[LABEL_BITS+:4];
                            winner<=rank_a>=parent_q[LABEL_BITS+:4]?ra:walk;
                            loser<=rank_a>=parent_q[LABEL_BITS+:4]?walk:ra;
                            rank_update<=rank_a==parent_q[LABEL_BITS+:4];new_rank<=rank_a+1'b1;state<=LINK;
                        end
                LINK: state<=RANK;
                RANK: begin acc<=winner;ni<=ni+1'b1;state<=NEXT;end
                F_REQ: state<=F_WAIT;
                F_WAIT: begin
                    flat_seed<=seed_q;
                    if(parent_q[LABEL_BITS-1:0]==flat) begin flat_root<=flat;state<=F_WRITE;end
                    else begin walk<=parent_q[LABEL_BITS-1:0];state<=F_ROOT_REQ;end
                end
                F_ROOT_REQ: state<=F_ROOT_WAIT;
                F_ROOT_WAIT: if(parent_q[LABEL_BITS-1:0]==walk) begin flat_root<=walk;state<=F_WRITE;end
                             else begin walk<=parent_q[LABEL_BITS-1:0];state<=F_ROOT_REQ;end
                F_WRITE: if({1'b0,flat}+1==next_label) begin flat<=1;state<=M_REQ;end
                         else begin flat<=flat+1'b1;state<=F_REQ;end
                M_REQ: state<=M_WAIT;
                M_WAIT: begin flat_root<=parent_q[LABEL_BITS-1:0];state<=M_FLAG_REQ;end
                M_FLAG_REQ: state<=M_FLAG_WAIT;
                M_FLAG_WAIT: if({1'b0,flat}+1==next_label) begin state<=IDLE;busy<=0;done<=1;end
                             else begin flat<=flat+1'b1;state<=M_REQ;end
                default: begin end
            endcase
        end
    end
endmodule
