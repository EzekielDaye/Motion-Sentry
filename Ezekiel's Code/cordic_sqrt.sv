`timescale 1ns / 1ps
`default_nettype none
// Actually Newton -Raphson 
//Just kept module name the same for testing
module CordicSqrt(
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] input_value,  // 32-bit unsigned fixed-point input (Q16.16)
    input  logic        start,        // Start signal
    output logic [31:0] sqrt_out,     // 32-bit unsigned fixed-point output (Q16.16)
    output logic        ready         // Ready signal
);
    // Internal registers
    logic [31:0] x;                   // Current approximation of the square root (Q16.16)
    logic [31:0] x_next;              // Next approximation
    logic [63:0] temp;                // Temporary value for intermediate calculations
    integer iteration;                // Iteration counter
    logic busy;                       // Busy signal to indicate ongoing computation

    localparam TOTAL_ITERATIONS = 16; // Max iterations for Newton-Raphson (sufficient for Q16.16)

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all registers
            x         <= 32'd0;
            x_next    <= 32'd0;
            temp      <= 64'd0;
            iteration <= 0;
            busy      <= 1'b0;
            sqrt_out  <= 32'd0;
            ready     <= 1'b0;
        end else if (start && !busy) begin
            // Initialize computation
            x         <= (input_value > 32'd0) ? (input_value >> 1) : 32'd1; // Prevent divide-by-zero
            x_next    <= (input_value > 32'd0) ? (input_value >> 1) : 32'd1;\
            iteration <= 0;
            busy      <= 1'b1;
            ready     <= 1'b0;
        end else if (busy) begin
            // Perform iterative Newton-Raphson calculation
            temp = ((x * x) >> 16);            
            temp = (temp + input_value) << 16; \

            if (x != 0) begin
                x_next <= (temp / x) >> 1;     
                x <= x_next;                 
            end else begin
                x_next <= 32'd0;             
            end

            iteration <= iteration + 1;

           
            if (iteration >= TOTAL_ITERATIONS) begin
                sqrt_out <= x_next;        
                busy     <= 1'b0;
                ready    <= 1'b1;
            end
        end else begin
            ready <= 1'b0; // Deassert ready if not busy and not computing
        end
    end
endmodule

`default_nettype wire
