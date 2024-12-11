`timescale 1ns / 1ps
`default_nettype none

module PixelClassification(
    input  logic              clk,
    input  logic              rst,
    input  logic [7:0]        I_R,        // Current pixel's red value
    input  logic [7:0]        I_G,        // Current pixel's green value
    input  logic [7:0]        I_B,        // Current pixel's blue value
    input  logic [31:0]       E_R,        // Mean red value from background model (Q16.16)
    input  logic [31:0]       E_G,        // Mean green value from background model (Q16.16)
    input  logic [31:0]       E_B,        // Mean blue value from background model (Q16.16)
    input  logic [31:0]       SD_alpha,   // Standard deviation of alpha (Q16.16)
    input  logic [31:0]       SD_CD,      // Standard deviation of CD (Q16.16)
    input  logic signed [31:0] alpha,     // Precomputed brightness distortion
    input  logic signed [31:0] CD,        // Precomputed chromaticity distortion
    input  logic              valid_in,
    output logic [1:0]        classification,
    output logic              valid_out
);

    // ** Constants **
    localparam logic signed [31:0] E_ALPHA = 32'sd65536;
    localparam logic signed [31:0] E_CD    = 32'sd0;     
    localparam int                 K1      = 2;          
    localparam int                 K2      = 2;         
    localparam int                 K3      = 2;         

    // ** Internal Signals **
    logic [7:0]  I_R_buffered, I_G_buffered, I_B_buffered;    
    logic [31:0] E_R_buffered, E_G_buffered, E_B_buffered;     
    logic [31:0] SD_alpha_buffered, SD_CD_buffered;           
    logic valid_buffered;                                    

    logic [31:0] a_lo, a_hi, b; // Threshold values
    logic [1:0] classification_next; // Intermediate classification

    // ** Buffering Input Values **
    always_ff @(posedge clk) begin
        if (rst) begin
            I_R_buffered <= 8'd0;
            I_G_buffered <= 8'd0;
            I_B_buffered <= 8'd0;
            E_R_buffered <= 32'd0;
            E_G_buffered <= 32'd0;
            E_B_buffered <= 32'd0;
            SD_alpha_buffered <= 32'd0;
            SD_CD_buffered <= 32'd0;
            valid_buffered <= 1'b0;
        end else if (valid_in) begin
            I_R_buffered <= I_R;
            I_G_buffered <= I_G;
            I_B_buffered <= I_B;
            E_R_buffered <= E_R;
            E_G_buffered <= E_G;
            E_B_buffered <= E_B;
            SD_alpha_buffered <= SD_alpha;
            SD_CD_buffered <= SD_CD;
            valid_buffered <= valid_in;
        end
    end

    // ** Threshold Calculations **
    always_ff @(posedge clk) begin
        if (rst) begin
            a_lo <= 32'sd0;
            a_hi <= 32'sd0;
            b    <= 32'sd0;
        end else if (valid_buffered) begin
            a_lo <= $signed(E_ALPHA) - ($signed(K1) * $signed(SD_alpha_buffered));
            a_hi <= $signed(E_ALPHA) + ($signed(K2) * $signed(SD_alpha_buffered));
            b    <= $signed(E_CD) + ($signed(K3) * $signed(SD_CD_buffered));
        end
    end

    // ** Classification Logic **
    always_ff @(posedge clk) begin
        if (rst) begin
            classification_next <= 2'b00; // Default to background
        end else if (valid_buffered) begin
            if ($signed(CD) > $signed(b)) begin
                classification_next <= 2'b01; // Foreground
            end else if ($signed(alpha) < $signed(a_lo)) begin
                classification_next <= 2'b10; // Shadow
            end else if ($signed(alpha) > $signed(a_hi)) begin
                classification_next <= 2'b11; // Highlight
            end else begin
                classification_next <= 2'b00; // Background
            end
        end
    end

    // ** Output Classification **
    always_ff @(posedge clk) begin
        if (rst) begin
            classification <= 2'b00;
        end else begin
            classification <= classification_next;
        end
    end

    // ** Valid Out Signal **
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_buffered;
        end
    end

endmodule

`default_nettype wire
