`timescale 1ns/1ps
module tb_capture;
    reg clk=0; always #2 clk=~clk;
    reg rst_n=0,arm=0,trigger=0,adc_valid=1;
    reg [4:0] record_samples=0,line_id=0;
    reg signed [13:0] adc_data=0;
    wire arm_ready,armed,busy,line_done,capture_error;
    wire [15:0] data; wire [1:0] keep; wire [4:0] user;
    wire valid,last; reg ready=0;
    integer expected[0:15],seen=0,n_expected=0,id_expected=0;
    reg checking=0,stalled=0; reg [15:0] held_data;
    reg held_last; reg [4:0] held_user;
    reg [31:0] random_state=32'h9f14ab37;
    fmc150_axi_capture #(.MAX_SAMPLES(16),.COUNT_WIDTH(5)) dut(
        .adc_clk(clk),.rst_n(rst_n),.arm(arm),.trigger(trigger),.adc_valid(adc_valid),
        .record_samples(record_samples),.line_id(line_id),.adc_data(adc_data),
        .arm_ready(arm_ready),.armed(armed),.busy(busy),.line_done(line_done),
        .capture_error(capture_error),.m_axis_tdata(data),.m_axis_tkeep(keep),
        .m_axis_tuser(user),.m_axis_tvalid(valid),.m_axis_tlast(last),.m_axis_tready(ready));
    always @(negedge clk) begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        ready=random_state[0] && random_state[3];
    end
    always @(posedge clk) if (rst_n) begin
        if (stalled && (!valid || data!==held_data || last!==held_last || user!==held_user))
            $fatal(1,"Capture stream changed while stalled");
        stalled=valid && !ready; held_data=data; held_last=last; held_user=user;
        if (valid && ready) begin
            if (!checking || seen>=n_expected) $fatal(1,"Unexpected ADC output");
            if ($signed(data)!==expected[seen]) $fatal(1,"Capture value %0d got %0d expected %0d",seen,$signed(data),expected[seen]);
            if (last!==(seen==n_expected-1) || keep!==2'b11 || user!==id_expected)
                $fatal(1,"Capture sideband/TLAST error");
            seen=seen+1;
        end
    end
    task run_line;
        input integer n,id,base,hole;
        integer i;
        begin
            wait(arm_ready); @(negedge clk);
            n_expected=n; id_expected=id; seen=0; checking=1;
            for(i=0;i<n;i=i+1) expected[i]=(i==hole) ? 0 : base+i;
            record_samples=n; line_id=id; arm=1;
            @(negedge clk); arm=0; wait(armed);
            @(negedge clk); trigger=1; adc_data=base; adc_valid=hole!=0;
            for(i=1;i<n;i=i+1) begin
                @(negedge clk); trigger=0; adc_data=base+i; adc_valid=hole!=i;
            end
            @(negedge clk); trigger=0; adc_valid=1;
            wait(line_done); @(negedge clk);
            if(seen!=n || capture_error!==(hole>=0)) $fatal(1,"Capture count/error flag mismatch");
            checking=0;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        run_line(8,0,-8192,-1);
        run_line(1,24,8191,-1);
        run_line(16,5,-1234,3);
        @(negedge clk); record_samples=0; arm=1;
        @(negedge clk); arm=0;
        if(!capture_error || !arm_ready) $fatal(1,"Zero-length config accepted");
        @(negedge clk); record_samples=17; arm=1;
        @(negedge clk); arm=0;
        if(!capture_error || !arm_ready) $fatal(1,"Oversized config accepted");
        run_line(4,7,-500,-1);
        $display("PASS capture: signed words, 1/max length, stalls/TLAST, missing sample, invalid length, rearm");
        $finish;
    end
    initial begin #200000; $fatal(1,"Capture timeout"); end
endmodule
