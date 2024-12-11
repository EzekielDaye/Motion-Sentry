module counter(     input wire clk_in,
                    input wire rst_in,
                    input wire [20:0] period_in,
                    output logic [20:0] count_out,
                    output logic ready
              );

  always_ff @(posedge clk_in)begin
    if (rst_in==1)begin
      count_out<=0;
      ready <= 0;
    end else begin
      if (count_out+1==period_in)begin
        count_out<=0;
        ready <= 1;
      end else begin
        count_out<=count_out+1;
        ready <= 0;
      end
    end
  end
endmodule