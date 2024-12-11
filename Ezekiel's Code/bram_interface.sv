`timescale 1ns / 1ps
`default_nettype none
// Stephen LA BRAM INTERFACE
module bram_interface #(parameter DATA_WIDTH, parameter BRAM_DEPTH, parameter BRAM_DELAY)
					   (input wire clk, rst,
					    input wire [$clog2(BRAM_DEPTH)-1:0] addr,
					    input wire[DATA_WIDTH-1:0] line_in,
					    input wire we, en, 
					    input wire generator_mode, clr_bram, 
					    input wire next, 
					    output logic[DATA_WIDTH-1:0] line_out,
					    output logic valid_line_out,
					    output logic[$clog2(BRAM_DEPTH)-1:0] generator_addr,
					    output logic write_rdy);
	localparam BUFF_LEN = BRAM_DELAY+1;

	logic[DATA_WIDTH-1:0] bram_line_out;
	logic[BUFF_LEN-1:0] valid_line_pipe; 
	logic valid_line,nxt_valid_line, en_in, we_in;
	logic[$clog2(BRAM_DEPTH)-1:0] addr_in,buff_addr;
	logic[BUFF_LEN-1:0][DATA_WIDTH-1:0] line_out_buffer; 
	logic[$clog2(BRAM_DEPTH)-1:0] lines_stored;
	logic[$clog2(BUFF_LEN)-1:0] buff_place_ptr, buff_access_ptr;
	logic[$clog2(BUFF_LEN):0] els_in_buff;
	enum logic[2:0] {WRITE_MODE, PREP_GEN_MODE, FILL_BUFF, GENERATOR_MODE, SIMPLE_MODE, CLEAR_BRAM, RESET_GEN_MODE, ERROR_STATE} bramState;

    BRAM #(.DATA_WIDTH(DATA_WIDTH),.BRAM_DEPTH(BRAM_DEPTH),.RAM_PERFORMANCE("HIGH_PERFORMANCE")) 
    bram (.addra(addr_in),  
		  .dina(line_in),    
		  .clka(clk),    
		  .wea(we_in),      
		  .ena(en_in),      
		  .rsta(rst),    
		  .regcea(1'b1),
		  .douta(bram_line_out));

	always_comb begin
		if (generator_mode) begin
			en_in = 1;
			we_in = 0;
			addr_in = buff_addr; 
			if (bramState == GENERATOR_MODE) generator_addr = (buff_addr >= BUFF_LEN)? buff_addr-BUFF_LEN : lines_stored - (BUFF_LEN-buff_addr); 
			else if (bramState == SIMPLE_MODE) generator_addr = buff_access_ptr; 
			else generator_addr = 0; 
		end else begin
			en_in = en;
			we_in = we; 
			addr_in = addr; 
			generator_addr = 0;
		end
		valid_line = valid_line_pipe[BUFF_LEN-1];
		nxt_valid_line = valid_line_pipe[BUFF_LEN-2];
		line_out = 	(bramState == ERROR_STATE)? 0 : line_out_buffer[buff_access_ptr];
		write_rdy = bramState == WRITE_MODE && ~generator_mode && ~clr_bram;
		valid_line_out = (bramState == GENERATOR_MODE || bramState == SIMPLE_MODE) && generator_mode;
	end

	always_ff @(posedge clk) begin
		valid_line_pipe[BUFF_LEN-1:1] <= (bramState == PREP_GEN_MODE)? 0 : valid_line_pipe[BUFF_LEN-2:0]; 

		if (rst) begin
			valid_line_pipe[0] <= 0; 
			{buff_addr,buff_place_ptr,buff_access_ptr,els_in_buff} <= '0;
			{lines_stored,line_out_buffer} <= '0;
			bramState <= WRITE_MODE;
		end
		else begin
			case(bramState)
				WRITE_MODE: begin
					if (~clr_bram) begin 
						if (generator_mode) bramState <= PREP_GEN_MODE;
						if (we && write_rdy) lines_stored <= lines_stored + 1;
					end else lines_stored <= 0;
				end 

				PREP_GEN_MODE: begin
					{buff_addr,buff_place_ptr,buff_access_ptr,els_in_buff} <= '0; 
					valid_line_pipe[0] <= 1;
					bramState <= FILL_BUFF;
				end 

				FILL_BUFF: begin
					if (generator_mode) begin 
						if (buff_addr < BUFF_LEN) buff_addr <= buff_addr + 1; 
						if (buff_addr == BUFF_LEN-1) valid_line_pipe[0] <= 0;
						if (els_in_buff < BUFF_LEN) begin
							if (valid_line) begin 
								els_in_buff <= els_in_buff + 1;
								buff_place_ptr <= (buff_place_ptr == BUFF_LEN-1)? 0 : buff_place_ptr + 1;
								line_out_buffer[buff_place_ptr] <= bram_line_out;
							end 
						end else begin						
							if (lines_stored == 0) bramState <= ERROR_STATE;
							else bramState <= (lines_stored > BUFF_LEN)? GENERATOR_MODE : SIMPLE_MODE;					
						end
					end else bramState <= WRITE_MODE;
				end 

				GENERATOR_MODE: begin
					if (clr_bram) bramState <= CLEAR_BRAM;
					else if (~generator_mode) bramState <= RESET_GEN_MODE;
					else begin 
						if (next) begin
							buff_access_ptr <= (buff_access_ptr == BUFF_LEN-1)? 0 : buff_access_ptr + 1;
							buff_addr <= (buff_addr == lines_stored-1)? 0 : buff_addr + 1; 
							valid_line_pipe[0] <= 1;
						end else valid_line_pipe[0] <= 0;

						if (valid_line && ~next) els_in_buff <= els_in_buff + 1; 
						if (next && ~valid_line) els_in_buff <= els_in_buff - 1;

						if (nxt_valid_line) begin
							buff_place_ptr <= (buff_place_ptr == BUFF_LEN-1)? 0 : buff_place_ptr + 1;
							line_out_buffer[buff_place_ptr] <= bram_line_out;
						end 
					end
				end 

				SIMPLE_MODE: begin
					if (clr_bram) bramState <= CLEAR_BRAM;
					else if (~generator_mode) bramState <= RESET_GEN_MODE;				
					else if (next) buff_access_ptr <= (buff_access_ptr == lines_stored-1)? 0 : buff_access_ptr + 1;
				end 

				CLEAR_BRAM: begin					
					lines_stored <= 0;	
					bramState <= RESET_GEN_MODE;
				end 

				RESET_GEN_MODE: begin
					bramState <= WRITE_MODE;
					valid_line_pipe[0] <= 0; 
					if (clr_bram) lines_stored <= 0;
				end 

				ERROR_STATE: begin
					if (~generator_mode) bramState <= RESET_GEN_MODE;
				end 
			endcase 
		end
	end
	
endmodule 

`default_nettype wire
