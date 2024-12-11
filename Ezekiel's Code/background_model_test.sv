`timescale 1ns / 1ps
`default_nettype none

module BackgroundModelTest #(
    parameter integer WIDTH = 4,    // Width of the image
    parameter integer HEIGHT = 4,   // Height of the image
    parameter integer NUM_FRAMES = 3 // Number of frames for averaging
)(
    input  logic              clk,
    input  logic              rst,
    input  logic [7:0]        I_R,   // Input red channel
    input  logic [7:0]        I_G,   // Input green channel
    input  logic [7:0]        I_B,   // Input blue channel
    input  logic              valid_in,
    input  logic              btn0,  // Reset button
    output logic              valid_out,
    output logic [31:0]       E_R,   // Mean R in Q16.16 format
    output logic [31:0]       E_G,   // Mean G in Q16.16 format
    output logic [31:0]       E_B,   // Mean B in Q16.16 format
    output logic [31:0]       SD_R,  // Standard deviation R in Q16.16 format
    output logic [31:0]       SD_G,  // Standard deviation G in Q16.16 format
    output logic [31:0]       SD_B   // Standard deviation B in Q16.16 format
);

    // Constants
    localparam TOTAL_PIXELS = WIDTH * HEIGHT;

    // Accumulators for each pixel
    logic signed [47:0] sum_R_mem [0:TOTAL_PIXELS-1];
    logic signed [47:0] sum_G_mem [0:TOTAL_PIXELS-1];
    logic signed [47:0] sum_B_mem [0:TOTAL_PIXELS-1];

    logic signed [63:0] sum_sq_R_mem [0:TOTAL_PIXELS-1];
    logic signed [63:0] sum_sq_G_mem [0:TOTAL_PIXELS-1];
    logic signed [63:0] sum_sq_B_mem [0:TOTAL_PIXELS-1];

    // Per-pixel mean and variance
    logic signed [31:0] mean_R_mem [0:TOTAL_PIXELS-1];
    logic signed [31:0] mean_G_mem [0:TOTAL_PIXELS-1];
    logic signed [31:0] mean_B_mem [0:TOTAL_PIXELS-1];

    logic signed [31:0] variance_R_mem [0:TOTAL_PIXELS-1];
    logic signed [31:0] variance_G_mem [0:TOTAL_PIXELS-1];
    logic signed [31:0] variance_B_mem [0:TOTAL_PIXELS-1];

    // Pixel index and frame count
    logic [$clog2(TOTAL_PIXELS)-1:0] pixel_index;
    logic [$clog2(NUM_FRAMES)-1:0] frame_count;

    // Pipeline delay registers for pixel index
    logic [$clog2(TOTAL_PIXELS)-1:0] delayed_pixel_index;

    // CordicSqrt control signals
    logic        sqrt_start_R, sqrt_start_G, sqrt_start_B;
    logic        sqrt_ready_R, sqrt_ready_G, sqrt_ready_B;
    logic [31:0] sqrt_out_R, sqrt_out_G, sqrt_out_B;

    // Reset and initialize accumulators
    always_ff @(posedge clk) begin
        if (rst || btn0) begin
            frame_count <= 0;
            pixel_index <= 0;
            valid_out <= 0;
            E_R <= 0;
            E_G <= 0;
            E_B <= 0;
            SD_R <= 0;
            SD_G <= 0;
            SD_B <= 0;

            // Reset accumulators
            for (int i = 0; i < TOTAL_PIXELS; i++) begin
                sum_R_mem[i] <= 0;
                sum_G_mem[i] <= 0;
                sum_B_mem[i] <= 0;
                sum_sq_R_mem[i] <= 0;
                sum_sq_G_mem[i] <= 0;
                sum_sq_B_mem[i] <= 0;
            end
        end else if (valid_in) begin
            // Accumulate sums and squared sums for the current pixel
            sum_R_mem[pixel_index] <= sum_R_mem[pixel_index] + I_R;
            sum_G_mem[pixel_index] <= sum_G_mem[pixel_index] + I_G;
            sum_B_mem[pixel_index] <= sum_B_mem[pixel_index] + I_B;

            sum_sq_R_mem[pixel_index] <= sum_sq_R_mem[pixel_index] + I_R * I_R;
            sum_sq_G_mem[pixel_index] <= sum_sq_G_mem[pixel_index] + I_G * I_G;
            sum_sq_B_mem[pixel_index] <= sum_sq_B_mem[pixel_index] + I_B * I_B;

            // Increment pixel index and handle frame transitions
            if (pixel_index == TOTAL_PIXELS - 1) begin
                pixel_index <= 0;
                if (frame_count == NUM_FRAMES - 1) begin
                    frame_count <= 0;
                end else begin
                    frame_count <= frame_count + 1;
                end
            end else begin
                pixel_index <= pixel_index + 1;
            end
        end
    end

    // Compute mean and variance for each pixel
    always_ff @(posedge clk) begin
        if (frame_count == 0 && pixel_index == 0) begin
            for (int i = 0; i < TOTAL_PIXELS; i++) begin
                // Compute mean in Q16.16 format
                mean_R_mem[i] <= (sum_R_mem[i] << 16) / NUM_FRAMES;
                mean_G_mem[i] <= (sum_G_mem[i] << 16) / NUM_FRAMES;
                mean_B_mem[i] <= (sum_B_mem[i] << 16) / NUM_FRAMES;

                // Compute variance in Q16.16 format
                variance_R_mem[i] <= ((sum_sq_R_mem[i] / NUM_FRAMES) << 16) - ((mean_R_mem[i] * mean_R_mem[i]) >> 16);
                variance_G_mem[i] <= ((sum_sq_G_mem[i] / NUM_FRAMES) << 16) - ((mean_G_mem[i] * mean_G_mem[i]) >> 16);
                variance_B_mem[i] <= ((sum_sq_B_mem[i] / NUM_FRAMES) << 16) - ((mean_B_mem[i] * mean_B_mem[i]) >> 16);
            end
        end
    end

    // Start square root computation
    always_ff @(posedge clk) begin
        if (pixel_index == 0) begin
            sqrt_start_R <= 1'b1;
            sqrt_start_G <= 1'b1;
            sqrt_start_B <= 1'b1;
        end else begin
            sqrt_start_R <= 1'b0;
            sqrt_start_G <= 1'b0;
            sqrt_start_B <= 1'b0;
        end
    end

    // Synchronize delayed pixel index
    always_ff @(posedge clk) begin
        delayed_pixel_index <= pixel_index;
    end

    // Generate outputs
    always_ff @(posedge clk) begin
        if (sqrt_ready_R && sqrt_ready_G && sqrt_ready_B) begin
            SD_R <= sqrt_out_R;
            SD_G <= sqrt_out_G;
            SD_B <= sqrt_out_B;

            // Use delayed pixel index to align outputs
            E_R <= mean_R_mem[delayed_pixel_index];
            E_G <= mean_G_mem[delayed_pixel_index];
            E_B <= mean_B_mem[delayed_pixel_index];

            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

    // Instantiate CordicSqrt for each channel
    CordicSqrt sqrt_R (
        .clk(clk),
        .rst(rst),
        .input_value(variance_R_mem[delayed_pixel_index]),
        .start(sqrt_start_R),
        .sqrt_out(sqrt_out_R),
        .ready(sqrt_ready_R)
    );

    CordicSqrt sqrt_G (
        .clk(clk),
        .rst(rst),
        .input_value(variance_G_mem[delayed_pixel_index]),
        .start(sqrt_start_G),
        .sqrt_out(sqrt_out_G),
        .ready(sqrt_ready_G)
    );

    CordicSqrt sqrt_B (
        .clk(clk),
        .rst(rst),
        .input_value(variance_B_mem[delayed_pixel_index]),
        .start(sqrt_start_B),
        .sqrt_out(sqrt_out_B),
        .ready(sqrt_ready_B)
    );

endmodule

`default_nettype wire
