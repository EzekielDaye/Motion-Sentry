`timescale 1ns / 1ps
`default_nettype none

`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else /* ! SYNTHESIS */
`define FPATH(X) `"../../data/X`"
`endif  /* ! SYNTHESIS */

module image_digit #(
  parameter WIDTH=256, HEIGHT=256) (
  input wire pixel_clk_in,
  input wire rst_in,
  input wire [10:0] x_in,
  input wire [10:0] hcount_in,
  input wire [9:0] y_in, 
  input wire [9:0] vcount_in,
  input wire [3:0] digit,
  output logic [7:0] red_out,
  output logic [7:0] green_out,
  output logic [7:0] blue_out
  );

  // calculate rom address
  logic [$clog2(2*WIDTH*HEIGHT)-1:0] image_addr;

  //assign image_addr = (hcount_in - x_in) + ((vcount_in - y_in) * WIDTH);
  assign image_addr = (hcount_in - x_in) + ((vcount_in - y_in) * WIDTH);

  logic in_sprite;
  assign in_sprite = ((hcount_in >= x_in && hcount_in < (x_in + WIDTH)) &&
                      (vcount_in >= y_in && vcount_in < (y_in + HEIGHT)));
  //logic [15:0] addr_img;
  logic pixel_value;
  //logic [7:0]  clr_img;
  // Modify the module below to use your BRAMs!
  parameter THICKNESS = 3;
//   always_comb begin
//   case(digit)
//     4'b0000: begin
//         if((hcount_in-x_in>30 && hcount_in-x_in<=70)&&(vcount_in-y_in>10 && vcount_in-y_in<=10+THICKNESS)) begin
//             pixel_value = 1;
//         end else if((hcount_in-x_in>70 && hcount_in-x_in<=70+THICKNESS)&&(vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
//             pixel_value = 1;
//         end else if((hcount_in-x_in>30 && hcount_in-x_in<=70)&&(vcount_in-y_in>90 && vcount_in-y_in<=90+THICKNESS)) begin
//             pixel_value = 1;
//         end else if((hcount_in-x_in>30 && hcount_in-x_in<=30+THICKNESS)&&(vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
//             pixel_value = 1;
//         end else begin
//             pixel_value = 0;
//         end
//     end
//     default:pixel_value=0;
//   endcase
// end
  always_comb begin
    case (digit)
      4'b0000: begin // Digit "0"
        if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>10 && vcount_in-y_in<=10+THICKNESS)) begin
          pixel_value = 1; // Top horizontal segment
        end else if ((hcount_in-x_in>70 && hcount_in-x_in<=70+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Right vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>90 && vcount_in-y_in<=90+THICKNESS)) begin
          pixel_value = 1; // Bottom horizontal segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=30+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Left vertical segment
        end else begin
          pixel_value = 0;
        end
      end
  
      4'b0001: begin // Digit "1"
        if ((hcount_in-x_in>50 && hcount_in-x_in<=50+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Single vertical line
        end else begin
          pixel_value = 0;
        end
      end
  
      4'b0010: begin // Digit "2"
        if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>10 && vcount_in-y_in<=10+THICKNESS)) begin
          pixel_value = 1; // Top horizontal segment
        end else if ((hcount_in-x_in>70 && hcount_in-x_in<=70+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=50)) begin
          pixel_value = 1; // Top-right vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>50 && vcount_in-y_in<=50+THICKNESS)) begin
          pixel_value = 1; // Middle horizontal segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=30+THICKNESS) && (vcount_in-y_in>50 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Bottom-left vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>90 && vcount_in-y_in<=90+THICKNESS)) begin
          pixel_value = 1; // Bottom horizontal segment
        end else begin
          pixel_value = 0;
        end
      end
  
      4'b0011: begin // Digit "3"
        if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>10 && vcount_in-y_in<=10+THICKNESS)) begin
          pixel_value = 1; // Top horizontal segment
        end else if ((hcount_in-x_in>70 && hcount_in-x_in<=70+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Right vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>50 && vcount_in-y_in<=50+THICKNESS)) begin
          pixel_value = 1; // Middle horizontal segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>90 && vcount_in-y_in<=90+THICKNESS)) begin
          pixel_value = 1; // Bottom horizontal segment
        end else begin
          pixel_value = 0;
        end
      end
  
      4'b0100: begin // Digit "4"
        if ((hcount_in-x_in>30 && hcount_in-x_in<=30+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=50)) begin
          pixel_value = 1; // Top-left vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>50 && vcount_in-y_in<=50+THICKNESS)) begin
          pixel_value = 1; // Middle horizontal segment
        end else if ((hcount_in-x_in>70 && hcount_in-x_in<=70+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Right vertical segment
        end else begin
          pixel_value = 0;
        end
      end
  
      4'b0101: begin // Digit "5"
        if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>10 && vcount_in-y_in<=10+THICKNESS)) begin
          pixel_value = 1; // Top horizontal segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=30+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=50)) begin
          pixel_value = 1; // Top-left vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>50 && vcount_in-y_in<=50+THICKNESS)) begin
          pixel_value = 1; // Middle horizontal segment
        end else if ((hcount_in-x_in>70 && hcount_in-x_in<=70+THICKNESS) && (vcount_in-y_in>50 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Bottom-right vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>90 && vcount_in-y_in<=90+THICKNESS)) begin
          pixel_value = 1; // Bottom horizontal segment
        end else begin
          pixel_value = 0;
        end
      end
  
      4'b0110: begin // Digit "6"
        if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>10 && vcount_in-y_in<=10+THICKNESS)) begin
          pixel_value = 1; // Top horizontal segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=30+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Left vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>50 && vcount_in-y_in<=50+THICKNESS)) begin
          pixel_value = 1; // Middle horizontal segment
        end else if ((hcount_in-x_in>70 && hcount_in-x_in<=70+THICKNESS) && (vcount_in-y_in>50 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Bottom-right vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>90 && vcount_in-y_in<=90+THICKNESS)) begin
          pixel_value = 1; // Bottom horizontal segment
        end else begin
          pixel_value = 0;
        end
      end
  
      4'b0111: begin // Digit "7"
        if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>10 && vcount_in-y_in<=10+THICKNESS)) begin
          pixel_value = 1; // Top horizontal segment
        end else if ((hcount_in-x_in>70 && hcount_in-x_in<=70+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Right vertical segment
        end else begin
          pixel_value = 0;
        end
      end
  
      4'b1000: begin // Digit "8"
        if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>10 && vcount_in-y_in<=10+THICKNESS)) begin
          pixel_value = 1; // Top horizontal segment
        end else if ((hcount_in-x_in>70 && hcount_in-x_in<=70+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Right vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>50 && vcount_in-y_in<=50+THICKNESS)) begin
          pixel_value = 1; // Middle horizontal segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=30+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Left vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>90 && vcount_in-y_in<=90+THICKNESS)) begin
          pixel_value = 1; // Bottom horizontal segment
        end else begin
          pixel_value = 0;
        end
      end
  
      4'b1001: begin // Digit "9"
        if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>10 && vcount_in-y_in<=10+THICKNESS)) begin
          pixel_value = 1; // Top horizontal segment
        end else if ((hcount_in-x_in>70 && hcount_in-x_in<=70+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=90)) begin
          pixel_value = 1; // Right vertical segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=70) && (vcount_in-y_in>50 && vcount_in-y_in<=50+THICKNESS)) begin
          pixel_value = 1; // Middle horizontal segment
        end else if ((hcount_in-x_in>30 && hcount_in-x_in<=30+THICKNESS) && (vcount_in-y_in>10 && vcount_in-y_in<=50)) begin
          pixel_value = 1; // Top-left vertical segment
        end else begin
          pixel_value = 0;
        end
      end
  
      default: begin
        pixel_value = 0; // Default case
      end
    endcase
  end
  
  assign red_out =    !in_sprite ? 0: (pixel_value==1)? 8'hff : 8'h00;
  assign green_out =  !in_sprite ? 0: (pixel_value==1)? 8'hff : 8'h00;
  assign blue_out =   !in_sprite ? 0: (pixel_value==1)? 8'hff : 8'h00;
endmodule






`default_nettype none

