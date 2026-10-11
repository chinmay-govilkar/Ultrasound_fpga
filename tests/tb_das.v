`timescale 1ns/1ps
module tb_das;
    localparam NP=36,NL=25,ND=16,NV=NP*NL;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,sv=0,slast=0,sample_valid=0;
    reg [4:0] line=0; reg [3:0] a0=0,a1=0; reg [11:0] fraction=0;
    wire sr,req_valid,req_ready,rsp_valid,rsp_ready;
    wire [4:0] req_line; wire [3:0] req_a0,req_a1;
    wire signed [15:0] sample0,sample1;
    wire signed [31:0] out_data; wire out_valid,out_last,error;
    reg out_ready=0,req_gate=0,rsp_gate=0;
    reg we=0; reg [4:0] write_line=0; reg [3:0] write_addr=0;
    reg signed [15:0] write_data=0;
    wire matrix_ready,matrix_valid,address_error;
    reg [15:0] samples[0:NL*ND-1];
    reg [3:0] addr0[0:NV-1],addr1[0:NV-1];
    reg [11:0] fractions[0:NV-1]; reg valids[0:NV-1];
    reg [31:0] expected[0:NP-1];
    integer i,k,p,seen=0; reg stalled=0; reg [31:0] held_data; reg held_last;
    reg [31:0] random_state=32'h7f937baa;
    assign req_ready=matrix_ready && req_gate;
    assign rsp_valid=matrix_valid && rsp_gate;
    das_beamformer_top #(.ADDR_WIDTH(4),.PIXELS_PER_FRAME(3)) dut(
        .clk(clk),.rst_n(rst_n),.s_axis_tvalid(sv),.s_axis_tready(sr),
        .s_axis_line(line),.s_axis_addr0(a0),.s_axis_addr1(a1),.s_axis_fraction(fraction),
        .s_axis_sample_valid(sample_valid),.s_axis_tlast(slast),
        .mem_req_valid(req_valid),.mem_req_ready(req_ready),.mem_req_line(req_line),
        .mem_req_addr0(req_a0),.mem_req_addr1(req_a1),.mem_rsp_valid(rsp_valid),
        .mem_rsp_ready(rsp_ready),.mem_rsp_data0(sample0),.mem_rsp_data1(sample1),
        .m_axis_tdata(out_data),.m_axis_tvalid(out_valid),.m_axis_tlast(out_last),
        .m_axis_tready(out_ready),.protocol_error(error));
    das_memory_matrix #(.DEPTH_BITS(4)) matrix(
        .clk(clk),.rst_n(rst_n),.we(we),.current_line(write_line),.write_addr(write_addr),.data_in(write_data),
        .mem_req_valid(req_valid && req_gate),.mem_req_ready(matrix_ready),.mem_req_line(req_line),
        .mem_req_addr0(req_a0),.mem_req_addr1(req_a1),.mem_rsp_valid(matrix_valid),
        .mem_rsp_ready(rsp_ready && rsp_gate),.mem_rsp_data0(sample0),.mem_rsp_data1(sample1),
        .address_error(address_error));
    always @(negedge clk) begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        out_ready=random_state[0] && random_state[5];
        req_gate=random_state[2]; rsp_gate=random_state[3];
    end
    always @(posedge clk) if(rst_n) begin
        if(stalled && (!out_valid || out_data!==held_data || out_last!==held_last))
            $fatal(1,"DAS output changed while stalled");
        stalled=out_valid && !out_ready; held_data=out_data; held_last=out_last;
        if(out_valid && out_ready) begin
            if(seen>=NP || out_data!==expected[seen])
                $fatal(1,"DAS pixel %0d got %0d expected %0d",seen,out_data,$signed(expected[seen]));
            if(out_last!==(seen%3==2)) $fatal(1,"Frame TLAST wrong");
            seen=seen+1;
        end
    end
    initial begin
        $readmemh("build/hdl/samples.hex",samples);
        $readmemh("build/hdl/addr0.hex",addr0); $readmemh("build/hdl/addr1.hex",addr1);
        $readmemh("build/hdl/fractions.hex",fractions); $readmemh("build/hdl/valid.hex",valids);
        $readmemh("build/hdl/expected.hex",expected);
        repeat(4) @(negedge clk); rst_n=1;
        for(i=0;i<NL*ND;i=i+1) begin
            @(negedge clk); we=1; write_line=i/ND; write_addr=i%ND; write_data=samples[i];
        end
        @(negedge clk); we=0;
        for(p=0;p<NP;p=p+1) for(k=0;k<NL;k=k+1) begin
            i=p*NL+k;
            @(negedge clk); sv=1; line=k; a0=addr0[i]; a1=addr1[i];
            fraction=fractions[i]; sample_valid=valids[i]; slast=k==NL-1;
            // Last test frame contains a deliberate malformed final descriptor.
            if(p==NP-1 && k==NL-1) slast=0;
            @(posedge clk); while(!sr) @(posedge clk);
            @(negedge clk); sv=0;
        end
        wait(seen==NP); @(negedge clk);
        if(!error || address_error) $fatal(1,"Protocol/address status mismatch");
        $display("PASS DAS: 36 pixels x25, signed extremes, fractional Q12, invalid samples, RAM/request/output stalls, frame TLAST, protocol error");
        $finish;
    end
    initial begin #2000000; $fatal(1,"DAS timeout"); end
endmodule
