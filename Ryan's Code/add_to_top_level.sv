`timescale 1ns / 1ps
`default_nettype none


module add_to_top_level (
    output logic [3:0]  servo  //Signals sent to servo pins
    );
  assign servo[2] = 0;
  assign servo[3] = 0;

  // Start of servo control

  // Initialize the variables
  // Used and continuously calculated pwm signals: 
  logic[20:0] dc_in_x, dc_in_y, predict_x, predict_y, center_x, center_y;
  // Lets us know if each servo is ready to take in the next signal
  logic ready_x, ready_y;


  // Using the COM, gives us the corresponding pwm signal
  predict pwm_predict(
    .x_in(x_com),
    .y_in(y_com),
    .pwm_x(predict_x),
    .pwm_y(predict_y)
  );

  // Only sets signal used when servos are ready
  always_ff @(posedge clk_camera ) begin
    if (sys_rst_camera || (sw[7:6] != 01)) begin
      dc_in_x <= 0;
      dc_in_y <= 0;
    end else begin
      if (ready_x) begin
        dc_in_x <= predict_x;
      end if (ready_y) begin
        dc_in_y <= predict_y;
      end
    end
  end

  // Uses the found PWM signal and outputs it to their corresponding pins
  pwm x_servo(
    .clk_in(clk_camera),
    .rst_in(sys_rst_camera),
    .dc_in(dc_in_x),
    .sig_out(servo[0]),
    .ready(ready_x)
  );

  pwm y_servo(
    .clk_in(clk_camera),
    .rst_in(sys_rst_camera),
    .dc_in(dc_in_y),
    .sig_out(servo[1]),
    .ready(ready_y)
  );

endmodule // top_level


`default_nettype wire