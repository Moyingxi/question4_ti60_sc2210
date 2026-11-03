`timescale 1ns / 1ps
// 使用无二极管触点网络模型，覆盖三角闭合导致的鬼键；不直接注入扫描器内部状态。
module tb_matrix_controls;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg [15:0] contacts=0;
    reg [3:0] rows;
    wire [3:0] oe;
    wire freeze_press,replay_press,median_press,minus_press,plus_press,multi,armed;
    wire [15:0] pressed,stable;
    reg board_plus=1,board_minus=1;
    wire [10:0] threshold;
    wire median;
    matrix_controls #(32,4,4) dut (
        clk,rst_n,rows,oe,freeze_press,replay_press,median_press,minus_press,plus_press,
        pressed,stable,multi,armed
    );
    key_controls #(8) controls (
        clk,rst_n,board_plus,board_minus,1'b1,threshold,median,
        plus_press,minus_press,median_press
    );
    // 行与列视为8个节点，闭合开关连接节点；被驱动列的低电平沿连通分量传播。
    reg [7:0] low_nodes;
    integer pass,r,c;
    always @* begin
        low_nodes={oe,4'b0};
        for(pass=0;pass<8;pass=pass+1)
            for(r=0;r<4;r=r+1)
                for(c=0;c<4;c=c+1)
                    if(contacts[r*4+c] && (low_nodes[r] || low_nodes[c+4])) begin
                        low_nodes[r]=1;
                        low_nodes[c+4]=1;
                    end
        rows=~low_nodes[3:0];
    end
    integer events=0,freeze_events=0,replay_events=0,median_events=0;
    integer minus_events=0,plus_events=0;
    reg [15:0] last=0,previous=0;
    always @(negedge clk) begin
        if((oe & (oe-1)) != 0) $fatal(1,"multiple driven columns");
        if(!rst_n && oe!=0) $fatal(1,"reset must release columns");
        if(pressed!=0) begin
            if(previous!=0 || (pressed & (pressed-1))!=0) $fatal(1,"invalid pulse");
            events=events+1;last=pressed;
        end
        previous=pressed;
        if(freeze_press) freeze_events++;
        if(replay_press) replay_events++;
        if(median_press) median_events++;
        if(minus_press) minus_events++;
        if(plus_press) plus_events++;
    end
    task wait_cycles(input integer n);
        repeat(n) @(posedge clk);
        #2;
    endtask
    task release_all;
        contacts=0;wait_cycles(900);
        if(!armed) $fatal(1,"release failed to arm");
    endtask
    task click(input integer index);
        integer before_count;
        before_count=events;
        contacts=16'b1<<index;wait_cycles(900);
        if(events!=before_count+1 || last!=(16'b1<<index)) $fatal(1,"key position %0d",index);
        wait_cycles(900);
        if(events!=before_count+1) $fatal(1,"long hold repeated");
        release_all();
    endtask
    integer k,saved;
    initial begin
        // 上电按住中值键不能触发；必须先确认全部释放。
        contacts=16'h0004;wait_cycles(8);rst_n=1;wait_cycles(900);
        if(events!=0 || median!=1 || threshold!=130) $fatal(1,"startup held");
        release_all();
        for(k=0;k<16;k=k+1) click(k);
        if(freeze_events!=1 || replay_events!=1 || median_events!=1 ||
           minus_events!=1 || plus_events!=1 || median!=0 || threshold!=130)
            $fatal(1,"functional mapping or reserved keys");
        click(2);
        if(median!=1) $fatal(1,"matrix median resume");
        click(4);
        if(threshold!=120) $fatal(1,"matrix minus");
        click(5);
        if(threshold!=130) $fatal(1,"matrix plus");
        // 短抖动均小于消抖时间，随后稳定按下只触发一次。
        saved=events;
        repeat(7) begin contacts=4;wait_cycles(25);contacts=0;wait_cycles(25);end
        if(events!=saved) $fatal(1,"bounce triggered");
        release_all();click(2);
        // 同列双键、同排双键、对角双键，以及三角鬼键都禁止功能。
        for(k=0;k<4;k=k+1) begin
            saved=events;
            case(k)
                0:contacts=16'h0011;
                1:contacts=16'h0003;
                2:contacts=16'h0021;
                3:contacts=16'h0013;
            endcase
            wait_cycles(900);
            if(!multi || events!=saved || armed) $fatal(1,"multi/ghost %0d",k);
            contacts=1;wait_cycles(900);
            if(events!=saved) $fatal(1,"partial release retriggered");
            release_all();
        end
        // 不经全释放，滑到另一单键不能触发第二次。
        contacts=1;wait_cycles(900);saved=events;
        contacts=2;wait_cycles(900);
        if(events!=saved) $fatal(1,"sliding key retriggered");
        release_all();click(1);
        // 板载加减仍可使用；同拍有效保持原阈值。
        board_plus=0;wait_cycles(30);board_plus=1;wait_cycles(30);
        if(threshold!=140) $fatal(1,"board plus");
        board_minus=0;wait_cycles(30);board_minus=1;wait_cycles(30);
        if(threshold!=130) $fatal(1,"board minus");
        board_plus=0;board_minus=0;wait_cycles(30);
        if(threshold!=130) $fatal(1,"board opposite");
        board_plus=1;board_minus=1;wait_cycles(30);
        rst_n=0;wait_cycles(8);rst_n=1;release_all();
        if(threshold!=130 || median!=1) $fatal(1,"reset defaults");
        $display("PASS matrix controls: 16 positions, mapping, median, debounce, long hold, ghosting, partial release, startup, board keys");
        $finish;
    end
    initial begin #10000000; $fatal(1,"timeout"); end
endmodule
