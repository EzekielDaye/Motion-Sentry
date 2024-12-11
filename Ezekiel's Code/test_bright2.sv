
module BrightnessDistortion2(
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
    output logic [31:0]       SD_alpha, 
    output logic              valid_out
);

    // Internal signals
    logic signed [63:0] N; // Numerator
    logic signed [63:0] D; // Denominator
    logic signed [47:0] sigma_sum_sq; 
    logic               calc_valid;
    logic               sqrt_ready;
    logic [31:0]        sqrt_output;

    // Safeguard against zero standard deviation
    logic [15:0] safe_sigma_R, safe_sigma_G, safe_sigma_B;

    always_comb begin
        safe_sigma_R = (sigma_R == 16'd0) ? 16'd1 : sigma_R;
        safe_sigma_G = (sigma_G == 16'd0) ? 16'd1 : sigma_G;
        safe_sigma_B = (sigma_B == 16'd0) ? 16'd1 : sigma_B;
    end

    // Numerator and Denominator calculations
    always_ff @(posedge clk) begin
        if (rst) begin
            N <= 64'd0;
            D <= 64'd0;
            sigma_sum_sq <= 48'd0;
            calc_valid <= 1'b0;
        end else if (valid_in) begin
            // Numerator
            N <= ((I_R * E_R) * (1 << 16) / safe_sigma_R) +
                 ((I_G * E_G) * (1 << 16) / safe_sigma_G) +
                 ((I_B * E_B) * (1 << 16) / safe_sigma_B);

            // Denominator
            D <= ((E_R * E_R) * (1 << 16) / safe_sigma_R) +
                 ((E_G * E_G) * (1 << 16) / safe_sigma_G) +
                 ((E_B * E_B) * (1 << 16) / safe_sigma_B);

            // Sum of squared standard deviations
            sigma_sum_sq <= (safe_sigma_R * safe_sigma_R) +
                            (safe_sigma_G * safe_sigma_G) +
                            (safe_sigma_B * safe_sigma_B);

            calc_valid <= 1'b1;
        end else begin
            calc_valid <= 1'b0;
        end
    end

    // Calculate SD_alpha using CordicSqrt
    CordicSqrt sqrt_inst (
        .clk(clk),
        .rst(rst),
        .input_value(sigma_sum_sq / 3), 
        .start(calc_valid),
        .sqrt_out(sqrt_output),        
        .ready(sqrt_ready)
    );

    // Brightness distortion (alpha) and valid_out
    always_ff @(posedge clk) begin
        if (rst) begin
            alpha <= 32'sd0;
            SD_alpha <= 32'd0;
            valid_out <= 1'b0;
        end else if (sqrt_ready) begin
            SD_alpha <= sqrt_output << 8;
            alpha <= (D != 64'd0) ? ((N << 16) / D) : 32'sd0; 
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
