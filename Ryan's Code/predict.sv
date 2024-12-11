module predict (
    input wire[10:0] x_in,
    input wire[9:0] y_in,
    output logic[20:0] pwm_x,
    output logic[20:0] pwm_y);


    // Good y:
    // maxy = 290000
    // miny = 155000
    // x currently lags going left, closer when x=0
    // maxx = 385000
    // minx = 125000
    // x now worse whne close to x=0
    // minx changed to 140000
    localparam MAX_X = 375000;
    localparam MAX_Y = 290000;
    localparam MIN_X = 125000;
    localparam MIN_Y = 155000;
    localparam X_DIFF = MAX_X - MIN_X;
    localparam Y_DIFF = MAX_Y - MIN_Y;
    localparam WIDTH = 1280;
    localparam HEIGHT = 720;
    localparam X_MULTIPLIER = X_DIFF/WIDTH;
    localparam Y_MULTIPLIER = Y_DIFF/HEIGHT;

    always_comb begin
        pwm_x = MIN_X + ((WIDTH - x_in) * X_MULTIPLIER);
        pwm_y = MIN_Y + (y_in * Y_MULTIPLIER);
    end

    

endmodule