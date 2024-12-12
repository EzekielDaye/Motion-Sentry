module check_sum (
    input wire [7:0] frame1_data,
    input wire [7:0] frame2_data,
    input wire [15:0] distance,
    input wire [15:0] strength, 
    input wire [15:0] temperature,
    input wire [7:0] checksum,
    output logic checksum_valid
);

    logic [15:0] total_sum;
    logic [7:0] calculated_checksum;

    always_comb begin
        // Sum all input values except checksum
        total_sum = frame1_data + frame2_data + distance + strength + temperature;
        
        // Take the 8 lowest bits of the sum
        calculated_checksum = total_sum[7:0];
        
        // Compare calculated checksum with input checksum
        checksum_valid = (calculated_checksum == checksum);
    end

endmodule