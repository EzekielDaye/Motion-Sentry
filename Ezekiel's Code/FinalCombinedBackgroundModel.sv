`timescale 1ns / 1ps
`default_nettype none

module CombinedBackgroundModel #(
    parameter integer WIDTH = 4,
    parameter integer HEIGHT = 4,
    parameter integer NUM_FRAMES = 3,
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 336
)(
    input  logic               clk,
    input  logic               rst,
    input  logic [7:0]         I_R,
    input  logic [7:0]         I_G,
    input  logic [7:0]         I_B,
    input  logic               valid_in,
    input  logic               btn0,
    output logic               valid_out,
    // DRAM interface signals
    input  logic [DATA_WIDTH-1:0] ddr3_dq,
    input  logic [(DATA_WIDTH/8)-1:0] ddr3_dqs_n,
    input  logic [(DATA_WIDTH/8)-1:0] ddr3_dqs_p,
    output logic [ADDR_WIDTH-1:0] ddr3_addr,
    input  logic              ui_clk,
    input  logic              ui_clk_sync_rst, 
    output logic [2:0]          ddr3_ba,
    output logic                ddr3_ras_n,
    output logic                ddr3_cas_n,
    output logic                ddr3_we_n,
    output logic                ddr3_reset_n,
    output logic                ddr3_ck_p,
    output logic                ddr3_ck_n,
    output logic                ddr3_cke,
    output logic [(DATA_WIDTH/8)-1:0] ddr3_dm,
    output logic                ddr3_odt
);

    // Constants
    localparam TOTAL_PIXELS = WIDTH * HEIGHT;
    localparam BYTES_PER_PIXEL = 16;

    // Pixel index and frame count
    logic [$clog2(TOTAL_PIXELS)-1:0] pixel_index;
    logic [$clog2(NUM_FRAMES)-1:0] frame_count;

    // Temporary storage for running sums and sums of squares
    logic signed [47:0] sum_R, sum_G, sum_B;
    logic signed [63:0] sum_sq_R, sum_sq_G, sum_sq_B;

    logic signed [47:0] sum_CD, sum_BD;
    logic signed [63:0] sum_sq_CD, sum_sq_BD;

    // Intermediate values
    logic signed [31:0] mean_R, mean_G, mean_B;
    logic signed [31:0] variance_R, variance_G, variance_B;
    logic signed [31:0] variance_CD, variance_BD;
    logic signed [31:0] sqrt_out_R, sqrt_out_G, sqrt_out_B;
    logic signed [31:0] sqrt_out_CD, sqrt_out_BD;
    logic              sqrt_ready_R, sqrt_ready_G, sqrt_ready_B;
    logic              sqrt_ready_CD, sqrt_ready_BD;

    // DRAM state machine
    typedef enum logic [2:0] {IDLE, READ, UPDATE, WRITE_SUMS, FINALIZE, WRITE_RESULTS} dram_state_t;
    dram_state_t state;
    logic signed [31:0] chromaticity_delta_R, chromaticity_delta_G, chromaticity_delta_B;
    logic signed [31:0] chromaticity_distortion;
    logic signed [31:0] brightness_distortion;

    always_ff @(posedge clk) begin
        if (rst || btn0) begin
            state <= IDLE;
            sum_R <= 0;
            sum_G <= 0;
            sum_B <= 0;
            sum_sq_R <= 0;
            sum_sq_G <= 0;
            sum_sq_B <= 0;
            sum_CD <= 0;
            sum_BD <= 0;
            sum_sq_CD <= 0;
            sum_sq_BD <= 0;
            mean_R <= 0;
            mean_G <= 0;
            mean_B <= 0;
            pixel_index <= 0;
            frame_count <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (valid_in) begin
                        pixel_index <= 0;
                        state <= READ;
                    end
                end
                READ: begin
                    // Unstacker fetches sums and sums of squares from DRAM
                    sum_R     <= unstacker_tdata[143:96];
                    sum_G     <= unstacker_tdata[95:48];
                    sum_B     <= unstacker_tdata[47:0];
                    sum_sq_B  <= unstacker_tdata[207:144];
                    sum_sq_G  <= unstacker_tdata[271:208];
                    sum_sq_R  <= unstacker_tdata[335:272];
                    state <= UPDATE;
                end
                UPDATE: begin
                    // Update running sums and sums of squares
                    sum_R <= sum_R + I_R;
                    sum_G <= sum_G + I_G;
                    sum_B <= sum_B + I_B;

                    sum_sq_R <= sum_sq_R + I_R * I_R;
                    sum_sq_G <= sum_sq_G + I_G * I_G;
                    sum_sq_B <= sum_sq_B + I_B * I_B;

                    // Compute Chromaticity Distortion (CD)
                    
                    chromaticity_delta_R <= (I_R << 16) / (sum_R << 16) - (mean_R / sum_R);
                    chromaticity_delta_G <= (I_G << 16) / (sum_G << 16) - (mean_G / sum_G);
                    chromaticity_delta_B <= (I_B << 16) / (sum_B << 16) - (mean_B / sum_B);

                    
                    chromaticity_distortion <= chromaticity_delta_R**2 + chromaticity_delta_G**2 + chromaticity_delta_B**2;
                    sum_CD <= sum_CD + chromaticity_distortion;
                    sum_sq_CD <= sum_sq_CD + chromaticity_distortion**2;

                    // Compute Brightness Distortion (BD)
                    
                    brightness_distortion <= (sum_R + sum_G + sum_B) - (mean_R + mean_G + mean_B);
                    sum_BD <= sum_BD + brightness_distortion;
                    sum_sq_BD <= sum_sq_BD + brightness_distortion**2;

                    if (frame_count == NUM_FRAMES - 1) begin
                        state <= FINALIZE;
                    end else begin
                        frame_count <= frame_count + 1;
                        state <= WRITE_SUMS;
                    end
                end
                WRITE_SUMS: begin
                    if (stacker_ready) begin
                        stacker_tdata <= {sum_sq_R, sum_sq_G, sum_sq_B, sum_R, sum_G, sum_B};
                        stacker_tvalid <= 1;
                        state <= IDLE;
                    end else begin
                        stacker_tvalid <= 0;
                    end
                end
                FINALIZE: begin
                    // Final mean, variance, and standard deviation for CD and BD
                    variance_CD <= ((sum_sq_CD / NUM_FRAMES) - ((sum_CD / NUM_FRAMES)**2));
                    variance_BD <= ((sum_sq_BD / NUM_FRAMES) - ((sum_BD / NUM_FRAMES)**2));

                    if (sqrt_ready_CD && sqrt_ready_BD && sqrt_ready_R && sqrt_ready_G && sqrt_ready_B) begin
                        state <= WRITE_RESULTS;
                    end
                end
                WRITE_RESULTS: begin
                    if (stacker_ready) begin
                        stacker_tdata <= {sqrt_out_CD, sqrt_out_BD, sqrt_out_R, sqrt_out_G, sqrt_out_B, mean_R, mean_G, mean_B};
                        stacker_tvalid <= 1;
                        if (pixel_index == TOTAL_PIXELS - 1) begin
                            state <= IDLE;
                            pixel_index <= 0;
                        end else begin
                            pixel_index <= pixel_index + 1;
                            state <= IDLE;
                        end
                    end else begin
                        stacker_tvalid <= 0;
                    end
                end
            endcase
        end
    end

    // Additional Square Root Modules
    CordicSqrt sqrt_CD_inst (
        .clk(clk),
        .rst(rst),
        .input_value(variance_CD),
        .start(state == FINALIZE),
        .sqrt_out(sqrt_out_CD),
        .ready(sqrt_ready_CD)
    );

    CordicSqrt sqrt_BD_inst (
        .clk(clk),
        .rst(rst),
        .input_value(variance_BD),
        .start(state == FINALIZE),
        .sqrt_out(sqrt_out_BD),
        .ready(sqrt_ready_BD)
    );

    // CordicSqrt Instantiations
    CordicSqrt sqrt_R_inst (
        .clk(clk),
        .rst(rst),
        .input_value(variance_R),
        .start(state == FINALIZE),
        .sqrt_out(sqrt_out_R),
        .ready(sqrt_ready_R)
    );

    CordicSqrt sqrt_G_inst (
        .clk(clk),
        .rst(rst),
        .input_value(variance_G),
        .start(state == FINALIZE),
        .sqrt_out(sqrt_out_G),
        .ready(sqrt_ready_G)
    );

    CordicSqrt sqrt_B_inst (
        .clk(clk),
        .rst(rst),
        .input_value(variance_B),
        .start(state == FINALIZE),
        .sqrt_out(sqrt_out_B),
        .ready(sqrt_ready_B)
    );

    // Signals for stacker
    logic [DATA_WIDTH-1:0] stacker_tdata; // Data to be written to DRAM
    logic                  stacker_tvalid; // Valid signal for stacker
    logic                  fifo_wr_tvalid; // Write valid signal to DRAM FIFO
    logic                  fifo_wr_tready; // Write ready signal from DRAM FIFO
    logic [DATA_WIDTH-1:0] fifo_wr_tdata;  // Data to DRAM FIFO
    logic                  fifo_wr_tlast;  // Last signal for DRAM FIFO write

    // Signals for unstacker
    logic [DATA_WIDTH-1:0] unstacker_tdata; // Data read from DRAM
    logic                  unstacker_tvalid; // Valid signal for unstacker
    logic                  fifo_rd_tvalid; // Read valid signal from DRAM FIFO
    logic                  fifo_rd_tready; // Read ready signal to DRAM FIFO
    logic [DATA_WIDTH-1:0] fifo_rd_tdata;  // Data from DRAM FIFO
    logic                  fifo_rd_tlast;  // Last signal for DRAM FIFO read
    logic [ADDR_WIDTH-1:0] app_addr;         // Address for DRAM transactions
    logic [2:0]            app_cmd;          // Command (e.g., read/write)
    logic                  app_en;           // Enable signal for DRAM transaction
    logic [DATA_WIDTH-1:0] app_wdf_data;     // Write data for DRAM
    logic                  app_wdf_end;      // End of write burst
    logic                  app_wdf_wren;     // Write enable for DRAM
    logic                  app_rd_data_valid; // Read data valid signal from DRAM
    logic [DATA_WIDTH-1:0] app_rd_data;      // Read data from DRAM
    logic                  app_rdy;          // Ready signal for DRAM transactions
    logic                  app_wdf_rdy;      // Ready signal for DRAM write data
    logic                  init_calib_complete; // DRAM initialization complete

    




    // Stacker Instantiation
    stacker stacker_inst (
        .clk_in(clk),
        .rst_in(rst),
        .pixel_tvalid(valid_out),
        .pixel_tdata(stacker_tdata),
        .pixel_tlast(pixel_index == TOTAL_PIXELS - 1),
        .chunk_tvalid(fifo_wr_tvalid),
        .chunk_tready(fifo_wr_tready),
        .chunk_tdata(fifo_wr_tdata),
        .chunk_tlast(fifo_wr_tlast)
    );

    // Unstacker Instantiation
    unstacker unstacker_inst (
        .clk_in(clk),
        .rst_in(rst),
        .chunk_tvalid(fifo_rd_tvalid),
        .chunk_tready(fifo_rd_tready),
        .chunk_tdata(fifo_rd_tdata),
        .chunk_tlast(fifo_rd_tlast),
        .pixel_tvalid(unstacker_tvalid),
        .pixel_tready(1'b1),
        .pixel_tdata(unstacker_tdata),
        .pixel_tlast(unstacker_tlast)
    );

     // Traffic Generator for DRAM Management
    traffic_generator traffic_gen (
        .app_addr         (app_addr),
        .app_cmd          (app_cmd),
        .app_en           (app_en),
        .app_wdf_data     (app_wdf_data),
        .app_wdf_end      (app_wdf_end),
        .app_wdf_wren     (app_wdf_wren),
        .app_wdf_mask     (),
        .app_rd_data      (app_rd_data),
        .app_rd_data_valid(app_rd_data_valid),
        .app_rdy          (app_rdy),
        .app_wdf_rdy      (app_wdf_rdy),
        .init_calib_complete(init_calib_complete),
        .clk_in           (ui_clk), // where to get this?
        .rst_in           (ui_clk_sync_rst)
    );
        // DDR3 MIG Instantiation
    mig_7series_0 mig_inst (
        .ddr3_dq          (ddr3_dq),
        .ddr3_dqs_n       (ddr3_dqs_n),
        .ddr3_dqs_p       (ddr3_dqs_p),
        .ddr3_addr        (ddr3_addr),
        .ddr3_ba          (ddr3_ba),
        .ddr3_ras_n       (ddr3_ras_n),
        .ddr3_cas_n       (ddr3_cas_n),
        .ddr3_we_n        (ddr3_we_n),
        .ddr3_reset_n     (ddr3_reset_n),
        .ddr3_ck_p        (ddr3_ck_p),
        .ddr3_ck_n        (ddr3_ck_n),
        .ddr3_cke         (ddr3_cke),
        .ddr3_dm          (ddr3_dm),
        .ddr3_odt         (ddr3_odt),
        .app_addr         (app_addr),
        .app_cmd          (app_cmd),
        .app_en           (app_en),
        .app_wdf_data     (app_wdf_data),
        .app_wdf_end      (app_wdf_end),
        .app_wdf_wren     (app_wdf_wren),
        .app_rd_data      (app_rd_data),
        .app_rd_data_valid(app_rd_data_valid),
        .app_rdy          (app_rdy),
        .app_wdf_rdy      (app_wdf_rdy),
        .ui_clk           (ui_clk),
        .ui_clk_sync_rst  (ui_clk_sync_rst),
        .init_calib_complete(init_calib_complete)
    );

endmodule
`default_nettype wire
