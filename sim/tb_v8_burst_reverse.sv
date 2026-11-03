`timescale 1ns/1ps
module tb_v8_burst_reverse;
    reg clk=0,rst_n=0;always #5 clk=~clk;
    reg [127:0] data=0;reg valid=0,ready=0;
    wire sr,mv,empty;wire [127:0] result;
    v8_burst_reverse dut(clk,rst_n,data,valid,sr,result,mv,ready,empty);
    integer sent=0,got=0,i,k,cycle=0;reg [31:0] rng=32'h81372782;
    reg hold_valid=0;reg [127:0] hold_data;
    initial begin
        repeat(8) @(negedge clk);rst_n=1;
        while(got<1600) begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            ready=rng[0]|rng[2];
            if(!valid && sent<1600 && rng[3]) begin
                valid=1;
                for(i=0;i<4;i=i+1) data[i*32+:32]=sent*4+i;
            end
            @(posedge clk);
            if(hold_valid && (!mv || result!==hold_data)) $fatal(1,"output changed under stall");
            hold_valid=mv&&!ready;hold_data=result;
            if(mv&&ready) begin
                k=(got/16)*64+63-(got%16)*4;
                for(i=0;i<4;i=i+1) if(result[i*32+:32]!==k-i) $fatal(1,"reversal mismatch word%0d lane%0d",got,i);
                got=got+1;
            end
            if(valid&&sr) begin sent=sent+1;@(negedge clk);valid=0;end
            else @(negedge clk);
            cycle=cycle+1;if(cycle>20000)$fatal(1,"timeout");
        end
        repeat(3) @(negedge clk);
        if(!empty || mv || sent!=1600)$fatal(1,"drain");
        $display("PASS V8 reverse burst: 100 bursts, reversed words/lanes and stable backpressure");$finish;
    end
endmodule
