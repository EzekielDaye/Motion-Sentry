// Brightness Distortion Module with Standard Deviation
//FULLY FUNCTIONAL
`timescale 1ns / 1ps
`default_nettype none
module BrightnessDistortion(
    input  logic              clk,
    input  logic              rst,
    input  logic [7:0]        I_R,   
    input  logic [7:0]        I_G,    
    input  logic [7:0]        I_B,   
    input  logic [15:0]       E_R,    
    input  logic [15:0]       E_G,    
    input  logic [15:0]       E_B,   
    input  logic [15:0]       sigma_R,
    input  logic [15:0]       sigma_G,
    input  logic [15:0]       sigma_B,
    input  logic              valid_in,
    output logic signed [31:0] alpha,
    output logic              valid_out
);

    // Internal signals
    logic signed [63:0] N; // Numerator
    logic signed [63:0] D; // Denominator
    logic               calc_valid;

    // Safeguard against zero standard deviation 
    logic [15:0] safe_sigma_R, safe_sigma_G, safe_sigma_B;

    always_comb begin
        safe_sigma_R = (sigma_R == 16'd0) ? 16'd1 : sigma_R;
        safe_sigma_G = (sigma_G == 16'd0) ? 16'd1 : sigma_G;
        safe_sigma_B = (sigma_B == 16'd0) ? 16'd1 : sigma_B;
    end

    // Numerator and Denominator calculations
    always_ff @(posedge clk ) begin
        if (rst) begin
            N <= 64'd0;
            D <= 64'd0;
            calc_valid <= 1'b0;
        end else if (valid_in) begin
            // Numerator: Sum of normalized products of input and expected channels
            N <= ((I_R * E_R) * (1 << 16) / safe_sigma_R) +  
                 ((I_G * E_G) * (1 << 16) / safe_sigma_G) +
                 ((I_B * E_B) * (1 << 16) / safe_sigma_B);

            // Denominator: Sum of normalized squared expected channels
            D <= ((E_R * E_R) * (1 << 16) / safe_sigma_R) +
                 ((E_G * E_G) * (1 << 16) / safe_sigma_G) +
                 ((E_B * E_B) * (1 << 16) / safe_sigma_B);

            calc_valid <= 1'b1; // Indicate that N and D are ready
        end else begin
            calc_valid <= 1'b0;
        end
    end

    // Brightness distortion (alpha) calculation
    always_ff @(posedge clk ) begin
        if (rst) begin
            alpha <= 32'sd0;
            valid_out <= 1'b0;
        end else if (calc_valid) begin
            alpha <= (D != 64'd0) ? ((N << 16) / D) : 32'sd0; // Scale result back to Q16.16
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
`default_nettype wire