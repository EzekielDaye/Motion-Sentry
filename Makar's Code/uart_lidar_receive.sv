`timescale 1ns / 1ps
`default_nettype none

module uart_lidar_receive
  #(
    parameter INPUT_CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200
    )
   (
    input wire 	       clk_in,
    input wire 	       rst_in,
    input wire 	       rx_wire_in,
    input wire         rst_frame_cnt,
    output logic       new_data_out,
    output logic [7:0] data_byte_out,
    output logic [3:0] frame_counter
    );
    parameter BAUD_PERIOD = int'($floor(INPUT_CLOCK_FREQ/BAUD_RATE));
    parameter BAUD_PERIOD_HALF = int'($floor(BAUD_PERIOD/2));
    parameter THREE_QUEARTERS = int'($floor(BAUD_PERIOD*0.75));
    parameter ONE_QUEARTERS = int'($floor(BAUD_PERIOD*0.25));
    parameter FRAME = 9;
    logic [$clog2(BAUD_PERIOD)-1:0] baud_cnt;
    logic[3:0] frame_cnt;
    logic[3:0] bit_cnt;

    assign frame_counter = frame_cnt; 

    logic data_in;
    logic idle;
    always_ff@(posedge clk_in) begin
      if (rst_frame_cnt) begin
        frame_cnt<=0;
      end 
      if (rst_in)begin
        baud_cnt<=0;
        bit_cnt<=0;
        data_in<=0;
        idle<=1;
        frame_cnt<=0;
      end else begin
        if(rx_wire_in==0 && idle) begin
          idle<=0;
          baud_cnt<=0;
          bit_cnt<=0;
          data_in<=0;
          //frame_cnt<=0;

        end else if (!idle) begin
          if (bit_cnt==0) begin
            //check if first bit is 0
              if(baud_cnt>ONE_QUEARTERS && baud_cnt<BAUD_PERIOD_HALF) begin
                if(data_in!=0) begin
                    idle<=1;
                end else begin
                    idle<=0;
                end
              end
              new_data_out<=0;
          end else if (bit_cnt==9) begin
              //check if last bit is 1
              if(baud_cnt>BAUD_PERIOD_HALF && baud_cnt < THREE_QUEARTERS) begin
                if(data_in!=1) begin
                    idle<=1;
                end else begin
                    idle<=0;
                    new_data_out<=1;
                end
              end 
              // else if(baud_cnt>THREE_QUEARTERS) begin 
              //   if(new_data_out) begin
              //     new_data_out<=0;
              //     idle<=1; //? delete
              //   end else begin 
              //   new_data_out<=1;
              //   idle<=0;
              //   end
              // end else begin
              //   idle<=0;
              //   new_data_out<=0;
              // end 
              
          end else if(bit_cnt==10) begin
            //if(new_data_out) begin
            //    new_data_out<=0;
            //    idle<=1; //? delete
            //end else begin 
            //  new_data_out<=1;
            //  idle<=0;
            //end
            if(frame_cnt<8) begin
            frame_cnt <= frame_cnt+1;
            new_data_out<=0;
            idle<=1;
            
            end else begin
              frame_cnt <= 0;
              new_data_out<=0;
            idle<=1;
            end
            
          end else begin
            if(baud_cnt==BAUD_PERIOD_HALF+2) begin
                data_byte_out[bit_cnt-1]<=data_in;
            end
          end

          if(baud_cnt==BAUD_PERIOD-1) begin
              bit_cnt<=bit_cnt+1;
              baud_cnt<=0;
              data_in<=data_in;
          end else if (baud_cnt==BAUD_PERIOD_HALF) begin
              data_in<=rx_wire_in; 
              baud_cnt<=baud_cnt+1; 
          end else begin
              bit_cnt<=bit_cnt;
              if(bit_cnt==0 && baud_cnt<BAUD_PERIOD_HALF) begin
                data_in<=rx_wire_in;
              end else if(bit_cnt==9 && baud_cnt>BAUD_PERIOD_HALF && baud_cnt < THREE_QUEARTERS) begin
                data_in<=rx_wire_in;
              end
              baud_cnt<=baud_cnt+1;
          end

          //if(bit_cnt==0) begin
          //  frame_cnt<=frame_cnt;
          //end else(bit_cnt=)
        end
      end
    end     
   // TODO: module to read UART rx wire

endmodule // uart_receive

`default_nettype wire
