`timescale 1ns / 1ps
`default_nettype none

module velocity_direction_calc (
    input  wire         clk_in,
    input  wire         rst_in,
    input  wire [10:0]  x_com_in,
    input  wire [9:0]   y_com_in,
    input  wire         valid_in,     // Asserted when x_com and y_com are valid
    output logic signed [11:0] vx_out, // Velocity in x-direction
    output logic signed [10:0] vy_out, // Velocity in y-direction
    output logic [3:0]  direction_out, // Direction encoded as 4 bits: {Right, Left, Up, Down}
    output logic        valid_out     // Asserted when vx_out, vy_out, and direction_out are valid
);

    // Registers to store previous COM values
    logic [10:0] prev_x_com;
    logic [9:0]  prev_y_com;

    // Clock cycle counter
    logic [15:0] delta_time;      // Time interval between valid inputs
    logic [15:0] clock_counter;   // Counts clock cycles

    // Divider signals for velocity calculation
    logic        div_vx_start, div_vy_start;
    logic        div_vx_busy,  div_vy_busy;
    logic [31:0] div_vx_dividend, div_vy_dividend;
    logic [31:0] div_vx_divisor,  div_vy_divisor;
    logic [31:0] div_vx_quotient, div_vy_quotient;

    // Divider for Velocity X
    divider2 vx_div_inst (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_valid_in(div_vx_start),
        .dividend_in(div_vx_dividend),
        .divisor_in(div_vx_divisor),
        .quotient_out(div_vx_quotient),
        .busy_out(div_vx_busy)
    );

    // Divider for Velocity Y
    divider2 vy_div_inst (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_valid_in(div_vy_start),
        .dividend_in(div_vy_dividend),
        .divisor_in(div_vy_divisor),
        .quotient_out(div_vy_quotient),
        .busy_out(div_vy_busy)
    );

    // Internal Valid Flags
    logic vx_valid, vy_valid;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            // Reset all registers
            prev_x_com    <= 11'd0;
            prev_y_com    <= 10'd0;
            delta_time    <= 16'd0;
            clock_counter <= 16'd0;
            vx_out        <= 12'sd0;
            vy_out        <= 11'sd0;
            direction_out <= 4'd0;
            valid_out     <= 1'b0;
            div_vx_start  <= 1'b0;
            div_vy_start  <= 1'b0;
        end else begin
            // Clock counter increments
            clock_counter <= clock_counter + 1;

            // Update delta_time and previous COM values when valid_in is asserted
            if (valid_in) begin
                delta_time <= clock_counter;
                clock_counter <= 16'd0;
                prev_x_com <= x_com_in;
                prev_y_com <= y_com_in;

                // Prepare divider inputs
                div_vx_dividend <= $signed(x_com_in) - $signed(prev_x_com);
                div_vx_divisor  <= (delta_time != 0) ? {{16{1'b0}}, delta_time} : 32'd1;
                div_vx_start    <= 1'b1;

                div_vy_dividend <= $signed(y_com_in) - $signed(prev_y_com);
                div_vy_divisor  <= (delta_time != 0) ? {{16{1'b0}}, delta_time} : 32'd1;
                div_vy_start    <= 1'b1;
            end else begin
                // Deassert start signals after one clock cycle
                div_vx_start <= 1'b0;
                div_vy_start <= 1'b0;
            end

            // Capture VX output when divider is ready
            if (!div_vx_busy ) begin
                vx_out <= div_vx_quotient[11:0];
                vx_valid <= 1'b1;
            end

            // Capture VY output when divider is ready
            if (!div_vy_busy) begin
                vy_out <= div_vy_quotient[10:0];
                vy_valid <= 1'b1;
            end

            // Combine outputs and determine direction when both velocities are ready
            if (vx_valid && vy_valid) begin
                valid_out <= 1'b1;
                vx_valid <= 1'b0;
                vy_valid <= 1'b0;

                // Determine direction
                direction_out[3] <= (vx_out > 0);  // Right
                direction_out[2] <= (vx_out < 0);  // Left
                direction_out[1] <= (vy_out > 0);  // Up
                direction_out[0] <= (vy_out < 0);  // Down
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule
`default_nettype wire
