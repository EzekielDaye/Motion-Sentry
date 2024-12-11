module pwm(   input wire clk_in,
              input wire rst_in,
              input wire [20:0] dc_in,
              output logic sig_out,
              output logic ready);
 
    logic [20:0] count;
    counter mc (.clk_in(clk_in),
                .rst_in(rst_in),
                .period_in(2000000),
                .count_out(count),
                .ready(ready));
    assign sig_out = count<dc_in; //very simple threshold check
endmodule