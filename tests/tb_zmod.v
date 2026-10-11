`timescale 1ns/1ps
module tb_zmod;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,arm=0,trigger=0,adc_valid=1,channel=0;
    reg source_ready=0,source_error=0,out_ready=0;
    reg [31:0] adc_data=0;
    reg [4:0] count=0,line=0;
    wire input_ready,arm_ready,armed,busy,done,error;
    wire [15:0] data; wire [1:0] keep; wire [4:0] user;
    wire valid,last;
    integer expected[0:15],seen=0,n_expected=0,id_expected=0;
    reg check_output=0,stalled=0;
    reg [15:0] held_data; reg held_last; reg [4:0] held_user;
    reg [31:0] random_state=32'h25392535;
    ultrasound_engine_top #(.MAX_SAMPLES(16)) dut(
        .adc_clk(clk),.rst_n(rst_n),.arm(arm),.trigger(trigger),
        .cDataAxisTdata(adc_data),.cDataAxisTvalid(adc_valid),.cDataAxisTready(input_ready),
        .receiver_channel(channel),.source_ready(source_ready),.source_error(source_error),
        .record_samples(count),.line_id(line),.arm_ready(arm_ready),.armed(armed),
        .busy(busy),.line_done(done),.capture_error(error),
        .m_axis_tdata(data),.m_axis_tkeep(keep),.m_axis_tuser(user),
        .m_axis_tvalid(valid),.m_axis_tlast(last),.m_axis_tready(out_ready));
    always @(negedge clk) begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        out_ready=random_state[0] && random_state[4];
    end
    always @(posedge clk) if(rst_n) begin
        if(input_ready!==1'b1) $fatal(1,"Zmod source was backpressured");
        if(stalled && (!valid || data!==held_data || last!==held_last || user!==held_user))
            $fatal(1,"Zmod packet changed while stalled");
        stalled=valid && !out_ready; held_data=data; held_last=last; held_user=user;
        if(valid && out_ready) begin
            if(!check_output || seen>=n_expected || $signed(data)!==expected[seen])
                $fatal(1,"Wrong physical channel or sample %0d value %0d",seen,$signed(data));
            if(last!==(seen==n_expected-1) || keep!==2'b11 || user!==id_expected)
                $fatal(1,"Zmod sideband mismatch");
            seen=seen+1;
        end
    end
    task run_line;
        input integer n,id,ch,hole,overflow_at;
        integer i,a,b;
        begin
            wait(arm_ready); @(negedge clk);
            n_expected=n;id_expected=id;seen=0;check_output=1;
            for(i=0;i<n;i=i+1) begin
                a=-32768+i; b=32767-i;
                expected[i]=i==hole ? 0 : (ch==0 ? a : b);
            end
            count=n;line=id;channel=ch;arm=1;
            @(negedge clk);arm=0;wait(armed);
            // Changing the command input after arming must not switch channels.
            channel=1-ch;
            for(i=0;i<n;i=i+1) begin
                @(negedge clk);trigger=i==0;adc_valid=i!=hole;source_error=i==overflow_at;
                a=-32768+i;b=32767-i;adc_data={a[15:0],b[15:0]};
            end
            @(negedge clk);trigger=0;adc_valid=1;source_error=0;
            wait(done);@(negedge clk);
            if(seen!=n || error!==((hole>=0)||(overflow_at>=0)))
                $fatal(1,"Zmod record count/error mismatch");
            check_output=0;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        count=2;arm=1;repeat(3) @(negedge clk);
        if(armed || arm_ready) $fatal(1,"Armed before controller ready");
        arm=0;source_ready=1;source_error=1;@(negedge clk);
        if(arm_ready) $fatal(1,"Armed with controller error");
        source_error=0;
        run_line(8,0,0,-1,-1);
        run_line(1,24,1,-1,-1);
        run_line(16,4,1,3,-1);
        run_line(4,5,0,-1,2);
        run_line(4,6,0,-1,-1);
        $display("PASS Zmod: CH1 upper/CH2 lower, int16 rails, latched selection, always ready, stalls, readiness/overflow/missing samples");
        $finish;
    end
    initial begin #300000; $fatal(1,"Zmod timeout");end
endmodule
