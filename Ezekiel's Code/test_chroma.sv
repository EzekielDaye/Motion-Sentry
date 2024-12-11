`timescale 1ns / 1ps
`default_nettype none

module ChromaticityDistortionTest(
    input  logic              clk,
    input  logic              rst,
    input  logic [7:0]        I_R,
    input  logic [7:0]        I_G,
    input  logic [7:0]        I_B,
    input  logic [15:0]       E_R,
    input  logic [15:0]       E_G,
    input  logic [15:0]       E_B,
    input  logic signed [31:0] alpha,
    input  logic              valid_in,
    output logic [31:0]       CD,        
    output logic              valid_out
);

    // Internal signals
    logic signed [31:0] alpha_E_R, alpha_E_G, alpha_E_B;
    logic signed [31:0] delta_R, delta_G, delta_B;      
    logic signed [47:0] delta_R_sq, delta_G_sq, delta_B_sq; 
    logic signed [31:0] sum_deltas;  
    logic               sum_ready;
    logic [31:0]        sqrt_input;  
    logic               sqrt_valid_out;
    logic [3:0]         valid_pipeline; 

    // Compute alpha * E_C (scaled to Q16.16)
    always_ff @(posedge clk ) begin
        if (rst) begin
            alpha_E_R <= 32'd0;
            alpha_E_G <= 32'd0;
            alpha_E_B <= 32'd0;
        end else if (valid_in) begin
            alpha_E_R <= (alpha * E_R) >>> 16; 
            alpha_E_G <= (alpha * E_G) >>> 16;  
            alpha_E_B <= (alpha * E_B) >>> 16;  
        end
    end

    // Compute delta values (avoiding unnecessary scaling)
    always_ff @(posedge clk) begin
        if (rst) begin
            delta_R <= 32'd0;
            delta_G <= 32'd0;
            delta_B <= 32'd0;
        end else if (valid_in) begin
            // Delta calculation directly in Q16.16 without excessive scaling
            delta_R <= (E_R != 0) ? (((I_R <<< 16) - alpha_E_R) / E_R) : 32'd0;  
            delta_G <= (E_G != 0) ? (((I_G <<< 16) - alpha_E_G) / E_G) : 32'd0;  
            delta_B <= (E_B != 0) ? (((I_B <<< 16) - alpha_E_B) / E_B) : 32'd0;  
        end
    end

    // Compute squared deltas and sum them up
    always_ff @(posedge clk) begin
        if (rst) begin
            delta_R_sq <= 48'd0;
            delta_G_sq <= 48'd0;
            delta_B_sq <= 48'd0;
            sum_deltas <= 32'd0;
            sum_ready <= 1'b0;
        end else if (valid_in) begin
            // Compute squared deltas in Q32.32 (delta in Q16.16)
            delta_R_sq <= delta_R * delta_R;  // Q32.32
            delta_G_sq <= delta_G * delta_G;  
            delta_B_sq <= delta_B * delta_B;  

            // Compute the sum of squared deltas and scale to Q16.16
            sum_deltas <= (delta_R_sq + delta_G_sq + delta_B_sq) >>> 16; 
            sum_ready <= 1'b1;
        end else begin
            sum_ready <= 1'b0;
        end
    end

    // Stable square root input with timing alignment
    always_ff @(posedge clk) begin
        if (rst) begin
            sqrt_input <= 32'd0;
        end else if (sum_ready) begin
            sqrt_input <= sum_deltas;  // Pass scaled input to square root module
        end
    end

    // Valid signal pipeline for synchronization
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_pipeline <= 4'd0;
        end else begin
            valid_pipeline <= {valid_pipeline[2:0], sum_ready}; // Delay valid signals
        end
    end

    CordicSqrt sqrt_inst (
        .clk(clk),
        .rst(rst),
        .input_value(sqrt_input),
        .start(valid_pipeline[3]), 
        .sqrt_out(CD),           
        .ready(sqrt_valid_out)    
    );

    // Handle valid output signal
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_out <= 1'b0;
        end else begin
            valid_out <= sqrt_valid_out;  // Indicate when CD is valid
        end
    end

endmodule
