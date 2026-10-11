`timescale 1ns/1ps
module tb_math;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,input_valid=0;
    reg signed [17:0] x=0,z=0,tx=0,tz=0;
    wire [38:0] squared; wire valid;
    reg [63:0] expected[0:2]; integer seen=0;
    das_channel_math dut(.clk(clk),.rst_n(rst_n),.input_valid(input_valid),
        .focal_x(x),.focal_z(z),.transducer_x(tx),.transducer_z(tz),
        .distance_squared(squared),.output_valid(valid));
    always @(posedge clk) if(rst_n && valid) begin
        if(seen>=3 || squared!==expected[seen][38:0]) $fatal(1,"Squared geometry wrong");
        seen=seen+1;
    end
    initial begin
        expected[0]=25; expected[1]=64'd262143*64'd262143*2; expected[2]=64'd50000*50000;
        repeat(3) @(negedge clk); rst_n=1;
        @(negedge clk); x=3; z=4; tx=0; tz=0; input_valid=1;
        @(negedge clk); x=-131072; z=131071; tx=131071; tz=-131072;
        @(negedge clk); x=0; z=50000; tx=0; tz=0;
        @(negedge clk); input_valid=0;
        repeat(6) @(negedge clk);
        if(seen!=3) $fatal(1,"Geometry valid pipeline wrong");
        $display("PASS geometry: signed differences, extreme widths, 50-mm coordinate, valid pipeline");
        $finish;
    end
    initial begin #10000; $fatal(1,"Geometry timeout"); end
endmodule
