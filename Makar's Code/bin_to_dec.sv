module bin_to_dec #(
    parameter INPUT_WIDTH = 16,                                    // Width of binary input
    parameter DECIMAL_DIGITS = 5                                 // Number of decimal digits needed
)(
    input  wire [INPUT_WIDTH-1:0]      binary_in,              // Binary input
    output logic [DECIMAL_DIGITS*4-1:0]  bcd_out                // BCD output (4 bits per digit)
);
    //$ceil(INPUT_WIDTH/3)*4+n
    // Internal signals
    logic [INPUT_WIDTH-1:0] binary_reg;
    //16 bit number is max 65535 => 5 digits, each 4 bits = 20 bits
    logic [DECIMAL_DIGITS*4-1:0] bcd_reg;
    
    always_comb begin
        binary_reg = binary_in;
        bcd_reg = '0;
        
        for (int i = INPUT_WIDTH-1; i >= 0; i--) begin
            
            for (int j = 0; j < 4*DECIMAL_DIGITS; j=j+4) begin
                if (bcd_reg[j+:4] > 4) begin
                    bcd_reg[j+:4] = bcd_reg[j+:4] + 3;
                end
            end
            
            bcd_reg = {bcd_reg[DECIMAL_DIGITS*4-2:0], binary_reg[i]};
        end
    end

    assign bcd_out = bcd_reg;
endmodule



