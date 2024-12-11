`timescale 1ns / 1ps
`default_nettype none

module top_level
  (
    input wire          clk_100mhz,
    output logic [15:0] led,
    // Camera interface
    input wire [7:0]    camera_d,    // 8-bit camera data
    output logic        cam_xclk,    // Camera clock output
    input wire          cam_hsync,   // Camera horizontal sync
    input wire          cam_vsync,   // Camera vertical sync
    input wire          cam_pclk,    // Camera pixel clock
    inout wire          i2c_scl,     // I2C clock
    inout wire          i2c_sda,     // I2C data
    input wire [15:0]   sw,          // User switches
    input wire [3:0]    btn,         // User buttons
    output logic [2:0]  rgb0,
    output logic [2:0]  rgb1,
    // Seven-segment display
    output logic [3:0]  ss0_an,      // Anode control for upper digits
    output logic [3:0]  ss1_an,      // Anode control for lower digits
    output logic [6:0]  ss0_c,       // Cathode control for upper digits
    output logic [6:0]  ss1_c,       // Cathode control for lower digits
    // HDMI output
    output logic [2:0]  hdmi_tx_p,   // HDMI positive signals
    output logic [2:0]  hdmi_tx_n,   // HDMI negative signals
    output logic        hdmi_clk_p, hdmi_clk_n, // Differential HDMI clock
    // DDR3 Interface
    inout wire [15:0]  ddr3_dq,
    inout wire [1:0]   ddr3_dqs_n,
    inout wire [1:0]   ddr3_dqs_p,
    output wire [12:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_ras_n,
    output wire        ddr3_cas_n,
    output wire        ddr3_we_n,
    output wire        ddr3_reset_n,
    output wire        ddr3_ck_p,
    output wire        ddr3_ck_n,
    output wire        ddr3_cke,
    output wire [1:0]  ddr3_dm,
    output wire        ddr3_odt
  );

  // Disable RGB LEDs
  assign rgb0 = 3'b0;
  assign rgb1 = 3'b0;

  // Clock and Reset Signals
  logic          sys_rst_camera;
  logic          sys_rst_pixel;
  logic          sys_rst_migref;

  logic          clk_camera;
  logic          clk_pixel;
  logic          clk_5x;
  logic          clk_xc;
  logic          clk_migref;
  logic          clk_ui;
  logic          sys_rst_ui;
  logic          clk_100_passthrough;

  // Clocking Wizards for generating required clocks
  cw_hdmi_clk_wiz wizard_hdmi
    (
     .sysclk(clk_100_passthrough),
     .clk_pixel(clk_pixel),
     .clk_tmds(clk_5x),
     .reset(0)
    );

  cw_fast_clk_wiz wizard_migcam
    (
     .clk_in1(clk_100mhz),
     .clk_camera(clk_camera),
     .clk_mig(clk_migref),
     .clk_xc(clk_xc),
     .clk_100(clk_100_passthrough),
     .reset(0)
    );

  // Assign camera's xclk to camera clock
  assign cam_xclk = clk_xc;

  assign sys_rst_camera = btn[0]; // Use btn[0] to reset camera logic
  assign sys_rst_pixel = btn[0];  // Use btn[0] to reset pixel logic
  assign sys_rst_migref = btn[0]; // Use btn[0] to reset MIG reference clock domain

  // Video Signal Generator Signals
  logic          hsync_hdmi;
  logic          vsync_hdmi;
  logic [10:0]   hcount_hdmi;
  logic [9:0]    vcount_hdmi;
  logic          active_draw_hdmi;
  logic          new_frame_hdmi;
  logic [5:0]    frame_count_hdmi;
  logic          nf_hdmi;

  // RGB Output Values
  logic [7:0]    red, green, blue;

  // ** Handling Input from the Camera **

  // Synchronizers to prevent metastability
  logic [7:0]    camera_d_buf [1:0];
  logic          cam_hsync_buf [1:0];
  logic          cam_vsync_buf [1:0];
  logic          cam_pclk_buf [1:0];

  always_ff @(posedge clk_camera) begin
    camera_d_buf[1] <= camera_d;
    camera_d_buf[0] <= camera_d_buf[1];
    cam_pclk_buf[1] <= cam_pclk;
    cam_pclk_buf[0] <= cam_pclk_buf[1];
    cam_hsync_buf[1] <= cam_hsync;
    cam_hsync_buf[0] <= cam_hsync_buf[1];
    cam_vsync_buf[1] <= cam_vsync;
    cam_vsync_buf[0] <= cam_vsync_buf[1];
  end

  logic [10:0] camera_hcount;
  logic [9:0]  camera_vcount;
  logic [15:0] camera_pixel;
  logic        camera_valid;

  // Pixel Reconstruction Module
  pixel_reconstruct pixel_reconstruct_inst
    (
      .clk_in(clk_camera),
      .rst_in(sys_rst_camera),
      .camera_pclk_in(cam_pclk_buf[0]),
      .camera_hs_in(cam_hsync_buf[0]),
      .camera_vs_in(cam_vsync_buf[0]),
      .camera_data_in(camera_d_buf[0]),
      .pixel_valid_out(camera_valid),
      .pixel_hcount_out(camera_hcount),
      .pixel_vcount_out(camera_vcount),
      .pixel_data_out(camera_pixel)
    );

  // ** Clock Domain Crossing FIFO (from clk_camera to clk_pixel) **
  logic empty;
  logic cdc_valid;
  logic [15:0] cdc_pixel;
  logic [10:0] cdc_hcount;
  logic [9:0]  cdc_vcount;

  // CDC FIFO
  fifo cdc_fifo
    (
      .wr_clk(clk_camera),
      .full(),
      .din({camera_hcount, camera_vcount, camera_pixel}),
      .wr_en(camera_valid),

      .rd_clk(clk_pixel),
      .empty(empty),
      .dout({cdc_hcount, cdc_vcount, cdc_pixel}),
      .rd_en(~empty)
    );

  assign cdc_valid = ~empty;



  logic [7:0] I_R, I_G, I_B;
  always_ff @(posedge clk_pixel) begin
    if (cdc_valid) begin
      I_R <= {cdc_pixel[15:11], 3'b0}; // 5-bit red to 8-bit
      I_G <= {cdc_pixel[10:5], 2'b0};  // 6-bit green to 8-bit
      I_B <= {cdc_pixel[4:0], 3'b0};   // 5-bit blue to 8-bit
    end
  end

  // Instantiate Background Subtraction Modules
  logic [15:0] E_R, E_G, E_B;
  logic [15:0] SD_R, SD_G, SD_B;
  logic        bg_valid_out;
  logic signed [31:0] alpha;
  logic        alpha_valid_out;
  logic [31:0] CD;
  logic        CD_valid_out;
  logic [1:0]  classification;
  logic        classification_valid_out;

  // ** DRAM Interface for Background Model **

  // Memory map addresses for background model storage, makes sure they don't overlap
  localparam BG_MODEL_BASE_ADDR = 27'd0; // Starting address in DRAM for background model
  localparam FRAME_DATA_BASE_ADDR = 27'd100_000; 


  logic [26:0]  bg_app_addr;
  logic [2:0]   bg_app_cmd;
  logic         bg_app_en;
  logic [127:0] bg_app_wdf_data;
  logic         bg_app_wdf_end;
  logic         bg_app_wdf_wren;
  logic [15:0]  bg_app_wdf_mask;
  logic [127:0] bg_app_rd_data;
  logic         bg_app_rd_data_end;
  logic         bg_app_rd_data_valid;
  logic         bg_app_rdy;
  logic         bg_app_wdf_rdy;

  
// Background Model Reader Integration
BackgroundModelReader #(
    .WIDTH(FRAME_WIDTH),
    .HEIGHT(FRAME_HEIGHT),
    .BG_MODEL_BASE_ADDR(BG_MODEL_BASE_ADDR)
) bg_model_reader_inst (
    .clk(clk_pixel),
    .rst(sys_rst_pixel),
    .valid_in(active_draw_hdmi), 
    .pixel_index(pixel_index),
    .E_R(E_R),
    .E_G(E_G),
    .E_B(E_B),
    .SD_R(SD_R),
    .SD_G(SD_G),
    .SD_B(SD_B),
    .cd(CD),
    .alpha(alpha),
    .valid_out(bg_model_valid_out),
    // DRAM Interface
    .app_addr(bg_reader_app_addr),
    .app_cmd(bg_reader_app_cmd),
    .app_en(bg_reader_app_en),
    .app_rd_data(bg_reader_app_rd_data),
    .app_rd_data_valid(bg_reader_app_rd_data_valid),
    .app_rdy(bg_reader_app_rdy),
    .init_calib_complete(init_calib_complete)
);
  //ADD DRAM INTERFACE I.E BG_READER_APP_ADDR, ETC.
  logic [ADDR_WIDTH-1:0] pixel_index;

// Updated Pixel Indexing Logic
always_ff @(posedge clk_pixel or posedge sys_rst_pixel) begin
    if (sys_rst_pixel) begin
        pixel_index <= 0;
    end else if (active_draw_hdmi) begin
        pixel_index <= hcount_hdmi + (vcount_hdmi * FRAME_WIDTH);
    end
end

// Background Model Save Data
always_comb begin
    if (sw[15]) begin
        BackgroundModelDRAM #(
            .WIDTH(FRAME_WIDTH),
            .HEIGHT(FRAME_HEIGHT),
            .NUM_FRAMES(10),
            .BG_MODEL_BASE_ADDR(BG_MODEL_BASE_ADDR)
        ) background_model_inst (
            .clk(clk_pixel),
            .rst(sys_rst_pixel),
            .I_R(I_R),
            .I_G(I_G),
            .I_B(I_B),
            .valid_in(cdc_valid),
            .btn0(btn[0]),
            .valid_out(bg_valid_out),
            // DRAM Interface
            .app_addr(bg_app_addr),
            .app_cmd(bg_app_cmd),
            .app_en(bg_app_en),
            .app_wdf_data(bg_app_wdf_data),
            .app_wdf_end(bg_app_wdf_end),
            .app_wdf_wren(bg_app_wdf_wren),
            .app_wdf_mask(bg_app_wdf_mask),
            .app_rd_data(bg_app_rd_data),
            .app_rd_data_end(bg_app_rd_data_end),
            .app_rd_data_valid(bg_app_rd_data_valid),
            .app_rdy(bg_app_rdy),
            .app_wdf_rdy(bg_app_wdf_rdy)
        );
    end
end




  
always_comb begin
    if (bg_model_valid_out) begin
        // Brightness Distortion
        BrightnessDistortion brightness_inst (
            .clk(clk_pixel),
            .rst(sys_rst_pixel),
            .I_R(I_R),
            .I_G(I_G),
            .I_B(I_B),
            .E_R(E_R),
            .E_G(E_G),
            .E_B(E_B),
            .valid_in(bg_model_valid_out),
            .alpha(alpha),
            .valid_out(alpha_valid_out)
        );

        // Chromaticity Distortion
        ChromaticityDistortion chromaticity_inst (
            .clk(clk_pixel),
            .rst(sys_rst_pixel),
            .I_R(I_R),
            .I_G(I_G),
            .I_B(I_B),
            .E_R(E_R),
            .E_G(E_G),
            .E_B(E_B),
            .alpha(alpha),
            .valid_in(alpha_valid_out),
            .CD(CD),
            .valid_out(CD_valid_out)
        );

        // Pixel Classification
        PixelClassification pixel_classification_inst (
            .clk(clk_pixel),
            .rst(sys_rst_pixel),
            .alpha(alpha),
            .CD(CD),
            .SD_alpha(SD_R),
            .SD_CD(SD_G),
            .valid_in(CD_valid_out),
            .classification(classification),
            .valid_out(classification_valid_out)
        );
    end
end

  // ** Frame Buffer for Displaying Classification Result **

  localparam FRAME_WIDTH = 1280;
  localparam FRAME_HEIGHT = 720;
  localparam FB_DEPTH = FRAME_WIDTH * FRAME_HEIGHT;
  localparam FB_SIZE = $clog2(FB_DEPTH);

  logic [FB_SIZE-1:0] addra;          // Address for writing to frame buffer
  logic               valid_mem_write; 
  logic [15:0]        pixel_mem_write; 

  always_ff @(posedge clk_pixel) begin
    if (classification_valid_out) begin
      addra <= cdc_hcount + cdc_vcount * FRAME_WIDTH;
      valid_mem_write <= 1'b1;

      // Map classification to pixel color
      case (classification)
        2'b00: pixel_mem_write <= 16'h07E0; // Background - Green
        2'b01: pixel_mem_write <= 16'hF800; // Foreground - Red
        2'b10: pixel_mem_write <= 16'h001F; // Shadow - Blue
        2'b11: pixel_mem_write <= 16'hFFE0; // Highlight - Yellow
        default: pixel_mem_write <= 16'hFFFF; // Default - White
      endcase
    end else begin
      valid_mem_write <= 1'b0;
    end
  end


  logic [127:0] frame_axis_tdata;
  logic         frame_axis_tvalid;
  logic         frame_axis_tlast;
  logic         frame_axis_tready;

  stacker frame_stacker_inst(
    .clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .pixel_tvalid(valid_mem_write),
    .pixel_tready(),
    .pixel_tdata(pixel_mem_write),
    .pixel_tlast((cdc_hcount == (FRAME_WIDTH - 1)) && (cdc_vcount == (FRAME_HEIGHT - 1))),
    .chunk_tvalid(frame_axis_tvalid),
    .chunk_tready(frame_axis_tready),
    .chunk_tdata(frame_axis_tdata),
    .chunk_tlast(frame_axis_tlast)
  );

  // FIFO for frame data (clk_pixel to clk_ui)
  logic [127:0] frame_ui_axis_tdata;
  logic         frame_ui_axis_tvalid;
  logic         frame_ui_axis_tlast;
  logic         frame_ui_axis_tready;
  logic         frame_ui_axis_prog_empty;

  ddr_fifo_wrap frame_data_fifo(
    .sender_rst(sys_rst_pixel),
    .sender_clk(clk_pixel),
    .sender_axis_tvalid(frame_axis_tvalid),
    .sender_axis_tready(frame_axis_tready),
    .sender_axis_tdata(frame_axis_tdata),
    .sender_axis_tlast(frame_axis_tlast),
    .receiver_clk(clk_ui),
    .receiver_axis_tvalid(frame_ui_axis_tvalid),
    .receiver_axis_tready(frame_ui_axis_tready),
    .receiver_axis_tdata(frame_ui_axis_tdata),
    .receiver_axis_tlast(frame_ui_axis_tlast),
    .receiver_axis_prog_empty(frame_ui_axis_prog_empty)
  );

  // ** DRAM Interface Signals for MIG **

  // These are the signals that the MIG IP needs for us to define!
  // MIG UI --> generic outputs
  logic [26:0]  app_addr;
  logic [2:0]   app_cmd;
  logic         app_en;
  // MIG UI --> write outputs
  logic [127:0] app_wdf_data;
  logic         app_wdf_end;
  logic         app_wdf_wren;
  logic [15:0]  app_wdf_mask;
  // MIG UI --> read inputs
  logic [127:0] app_rd_data;
  logic         app_rd_data_end;
  logic         app_rd_data_valid;
  // MIG UI --> generic inputs
  logic         app_rdy;
  logic         app_wdf_rdy;
  // MIG UI --> misc
  logic         app_sr_req;
  logic         app_ref_req;
  logic         app_zq_req;
  logic         app_sr_active;
  logic         app_ref_ack;
  logic         app_zq_ack;
  logic         init_calib_complete;

  // Adjusted Traffic Generator
  traffic_generator_with_bg_model readwrite_looper(
    // Outputs
    .app_addr         (app_addr[26:0]),
    .app_cmd          (app_cmd[2:0]),
    .app_en           (app_en),
    .app_wdf_data     (app_wdf_data[127:0]),
    .app_wdf_end      (app_wdf_end),
    .app_wdf_wren     (app_wdf_wren),
    .app_wdf_mask     (app_wdf_mask[15:0]),
    .app_sr_req       (app_sr_req),
    .app_ref_req      (app_ref_req),
    .app_zq_req       (app_zq_req),
    // Inputs
    .clk_in           (clk_ui),
    .rst_in           (sys_rst_ui),
    .app_rd_data      (app_rd_data[127:0]),
    .app_rd_data_end  (app_rd_data_end),
    .app_rd_data_valid(app_rd_data_valid),
    .app_rdy          (app_rdy),
    .app_wdf_rdy      (app_wdf_rdy),
    .app_sr_active    (app_sr_active),
    .app_ref_ack      (app_ref_ack),
    .app_zq_ack       (app_zq_ack),
    .init_calib_complete(init_calib_complete),
    // Frame data interface
    .write_axis_data  (frame_ui_axis_tdata),
    .write_axis_tlast (frame_ui_axis_tlast),
    .write_axis_valid (frame_ui_axis_tvalid),
    .write_axis_ready (frame_ui_axis_tready),
    .write_axis_smallpile(frame_ui_axis_prog_empty),
    .read_axis_data   (display_ui_axis_tdata),
    .read_axis_tlast  (display_ui_axis_tlast),
    .read_axis_valid  (display_ui_axis_tvalid),
    .read_axis_ready  (display_ui_axis_tready),
    .read_axis_af     (display_ui_axis_prog_full),
    // Background model interface
    .bg_app_addr      (bg_app_addr),
    .bg_app_cmd       (bg_app_cmd),
    .bg_app_en        (bg_app_en),
    .bg_app_wdf_data  (bg_app_wdf_data),
    .bg_app_wdf_end   (bg_app_wdf_end),
    .bg_app_wdf_wren  (bg_app_wdf_wren),
    .bg_app_wdf_mask  (bg_app_wdf_mask),
    .bg_app_rd_data   (bg_app_rd_data),
    .bg_app_rd_data_end(bg_app_rd_data_end),
    .bg_app_rd_data_valid(bg_app_rd_data_valid),
    .bg_app_rdy       (bg_app_rdy),
    .bg_app_wdf_rdy   (bg_app_wdf_rdy)
  );

  // the MIG IP!
  ddr3_mig ddr3_mig_inst
    (
      .ddr3_dq(ddr3_dq),
      .ddr3_dqs_n(ddr3_dqs_n),
      .ddr3_dqs_p(ddr3_dqs_p),
      .ddr3_addr(ddr3_addr),
      .ddr3_ba(ddr3_ba),
      .ddr3_ras_n(ddr3_ras_n),
      .ddr3_cas_n(ddr3_cas_n),
      .ddr3_we_n(ddr3_we_n),
      .ddr3_reset_n(ddr3_reset_n),
      .ddr3_ck_p(ddr3_ck_p),
      .ddr3_ck_n(ddr3_ck_n),
      .ddr3_cke(ddr3_cke),
      .ddr3_dm(ddr3_dm),
      .ddr3_odt(ddr3_odt),
      .sys_clk_i(clk_migref),
      .app_addr(app_addr),
      .app_cmd(app_cmd),
      .app_en(app_en),
      .app_wdf_data(app_wdf_data),
      .app_wdf_end(app_wdf_end),
      .app_wdf_wren(app_wdf_wren),
      .app_rd_data(app_rd_data),
      .app_rd_data_end(app_rd_data_end),
      .app_rd_data_valid(app_rd_data_valid),
      .app_rdy(app_rdy),
      .app_wdf_rdy(app_wdf_rdy),
      .app_sr_req(app_sr_req),
      .app_ref_req(app_ref_req),
      .app_zq_req(app_zq_req),
      .app_sr_active(app_sr_active),
      .app_ref_ack(app_ref_ack),
      .app_zq_ack(app_zq_ack),
      .ui_clk(clk_ui),
      .ui_clk_sync_rst(sys_rst_ui),
      .app_wdf_mask(app_wdf_mask),
      .init_calib_complete(init_calib_complete),
      .sys_rst(!sys_rst_migref) // active low
    );

  // FIFO from UI clock domain to pixel clock domain for display data
  logic [127:0] display_ui_axis_tdata;
  logic         display_ui_axis_tvalid;
  logic         display_ui_axis_tlast;
  logic         display_ui_axis_tready;
  logic         display_ui_axis_prog_full;

  logic [127:0] display_axis_tdata;
  logic         display_axis_tvalid;
  logic         display_axis_tlast;
  logic         display_axis_tready;
  logic         display_axis_prog_empty;

  ddr_fifo_wrap display_data_fifo(
    .sender_rst(sys_rst_ui),
    .sender_clk(clk_ui),
    .sender_axis_tvalid(display_ui_axis_tvalid),
    .sender_axis_tready(display_ui_axis_tready),
    .sender_axis_tdata(display_ui_axis_tdata),
    .sender_axis_tlast(display_ui_axis_tlast),
    .receiver_clk(clk_pixel),
    .receiver_axis_tvalid(display_axis_tvalid),
    .receiver_axis_tready(display_axis_tready),
    .receiver_axis_tdata(display_axis_tdata),
    .receiver_axis_tlast(display_axis_tlast),
    .receiver_axis_prog_empty(display_axis_prog_empty)
  );

  // Unstacker to convert 128-bit data back to pixels
  logic frame_buff_tvalid;
  logic frame_buff_tready;
  logic [15:0] frame_buff_tdata;
  logic        frame_buff_tlast;

  unstacker unstacker_inst(
    .clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .chunk_tvalid(display_axis_tvalid),
    .chunk_tready(display_axis_tready),
    .chunk_tdata(display_axis_tdata),
    .chunk_tlast(display_axis_tlast),
    .pixel_tvalid(frame_buff_tvalid),
    .pixel_tready(frame_buff_tready),
    .pixel_tdata(frame_buff_tdata),
    .pixel_tlast(frame_buff_tlast)
  );

  assign frame_buff_tready = 1'b1; // Always ready to accept data

  logic [15:0] frame_buff_raw;
  assign frame_buff_raw = frame_buff_tvalid ? frame_buff_tdata : 16'h0000;

  // ** HDMI Output Adjustments **

  // Extract RGB components from frame buffer data
  logic [7:0] fb_red, fb_green, fb_blue;
  always_ff @(posedge clk_pixel) begin
    fb_red   <= {frame_buff_raw[15:11], 3'b0};
    fb_green <= {frame_buff_raw[10:5], 2'b0};
    fb_blue  <= {frame_buff_raw[4:0], 3'b0};
  end

  // ** Center of Mass Module Integration **

  // Wires to connect to the center_of_mass module
  logic [10:0] x_com_calc;
  logic [9:0]  y_com_calc;
  logic        new_com;

  // Instantiate the center_of_mass module
  center_of_mass com_m(
    .clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .x_in(hcount_hdmi),
    .y_in(vcount_hdmi),
    .valid_in(mask_hdmi),     // Adjusted mask synchronized with HDMI signals
    .tabulate_in(nf_hdmi),    // New frame signal
    .x_out(x_com_calc),
    .y_out(y_com_calc),
    .valid_out(new_com)
  );

  // ** Crosshair Drawing Logic **

  // Crosshair color (e.g., red)
  localparam [7:0] CROSSHAIR_R = 8'd255;
  localparam [7:0] CROSSHAIR_G = 8'd0;
  localparam [7:0] CROSSHAIR_B = 8'd0;

  logic [7:0] ch_red, ch_green, ch_blue;

  // Crosshair size and thickness
  localparam integer CROSSHAIR_SIZE = 20;     // Length of crosshair lines
  localparam integer CROSSHAIR_THICKNESS = 2; // Thickness of crosshair lines

  always_ff @(posedge clk_pixel) begin
    if (sys_rst_pixel) begin
      ch_red <= 8'd0;
      ch_green <= 8'd0;
      ch_blue <= 8'd0;
    end else begin
      // Check if the current pixel is within the crosshair lines
      if (((hcount_hdmi >= x_com_calc - CROSSHAIR_SIZE) && (hcount_hdmi <= x_com_calc + CROSSHAIR_SIZE) &&
           (vcount_hdmi >= y_com_calc - CROSSHAIR_THICKNESS) && (vcount_hdmi <= y_com_calc + CROSSHAIR_THICKNESS)) ||
          ((vcount_hdmi >= y_com_calc - CROSSHAIR_SIZE) && (vcount_hdmi <= y_com_calc + CROSSHAIR_SIZE) &&
           (hcount_hdmi >= x_com_calc - CROSSHAIR_THICKNESS) && (hcount_hdmi <= x_com_calc + CROSSHAIR_THICKNESS))) begin
        ch_red <= CROSSHAIR_R;
        ch_green <= CROSSHAIR_G;
        ch_blue <= CROSSHAIR_B;
      end else begin
        ch_red <= 8'd0;
        ch_green <= 8'd0;
        ch_blue <= 8'd0;
      end
    end
  end

  // ** Bounding Box Drawing Logic **

  logic [7:0] box_red, box_green, box_blue;

  // Box color (e.g., green)
  localparam [7:0] BOX_R = 8'd0;
  localparam [7:0] BOX_G = 8'd255;
  localparam [7:0] BOX_B = 8'd0;

  always_ff @(posedge clk_pixel) begin
    if (sys_rst_pixel) begin
      box_red <= 8'd0;
      box_green <= 8'd0;
      box_blue <= 8'd0;
    end else begin
      // Check if the current pixel is on the bounding box edges
      if (((hcount_hdmi == min_x || hcount_hdmi == max_x) && vcount_hdmi >= min_y && vcount_hdmi <= max_y) ||
          ((vcount_hdmi == min_y || vcount_hdmi == max_y) && hcount_hdmi >= min_x && hcount_hdmi <= max_x)) begin
        box_red <= BOX_R;
        box_green <= BOX_G;
        box_blue <= BOX_B;
      end else begin
        box_red <= 8'd0;
        box_green <= 8'd0;
        box_blue <= 8'd0;
      end
    end
  end

  // ** Synchronize the Mask with HDMI Signals **

  // Implement a FIFO or delay line here to align 'classification' with HDMI signals
  // For demonstration purposes, we'll assume 'mask_hdmi' is generated accordingly

  logic mask_hdmi;
  // Synchronization logic to align 'classification' with HDMI signals
  // [Implement appropriate delay to match pipeline latency]
  assign mask_hdmi = (classification == 2'b01); // Foreground pixels

    // Instantiate the video_mux module
  // Use 'sw[0]' to control background removal
  logic remove_bg = sw[0];

// Define switches for control
wire [1:0] bg_in = sw[1:0];      // Use sw[1:0] for bg_in
wire [1:0] target_in = sw[3:2];  // Use sw[3:2] for target_in
wire remove_bg = sw[4];          // Use sw[4] for remove_bg

// Instantiate the video_mux module
video_mux mvm(
    .bg_in(bg_in),
    .target_in(target_in),
    .camera_pixel_in({cam_red, cam_green, cam_blue}),
    .classified_pixel_in({fb_red, fb_green, fb_blue}),
    .camera_y_in(camera_y_in), // If available, else set to 8'd0
    .channel_in(8'd0),         // If you have a selected channel, connect it
    .thresholded_pixel_in(mask_hdmi),
    .box_in({box_red, box_green, box_blue}),
    .crosshair_in({ch_red, ch_green, ch_blue}),
    .remove_bg(remove_bg),
    .pixel_out({red, green, blue})
);

  // HDMI Video Signal Generator
  video_sig_gen vsg
    (
     .pixel_clk_in(clk_pixel),
     .rst_in(sys_rst_pixel),
     .hcount_out(hcount_hdmi),
     .vcount_out(vcount_hdmi),
     .vs_out(vsync_hdmi),
     .hs_out(hsync_hdmi),
     .nf_out(nf_hdmi),
     .ad_out(active_draw_hdmi),
     .fc_out(frame_count_hdmi)
    );

  // HDMI Output Logic
  logic [9:0] tmds_10b [0:2]; // TMDS encoded signals
  logic       tmds_signal [0:2]; // TMDS serialized signals

  // TMDS Encoders
  tmds_encoder tmds_red(
      .clk_in(clk_pixel),
      .rst_in(sys_rst_pixel),
      .data_in(fb_red),
      .control_in(2'b0),
      .ve_in(active_draw_hdmi),
      .tmds_out(tmds_10b[2]));

  tmds_encoder tmds_green(
      .clk_in(clk_pixel),
      .rst_in(sys_rst_pixel),
      .data_in(fb_green),
      .control_in(2'b0),
      .ve_in(active_draw_hdmi),
      .tmds_out(tmds_10b[1]));

  tmds_encoder tmds_blue(
      .clk_in(clk_pixel),
      .rst_in(sys_rst_pixel),
      .data_in(fb_blue),
      .control_in({vsync_hdmi, hsync_hdmi}),
      .ve_in(active_draw_hdmi),
      .tmds_out(tmds_10b[0]));

  // TMDS Serializers
  tmds_serializer red_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(sys_rst_pixel),
      .tmds_in(tmds_10b[2]),
      .tmds_out(tmds_signal[2]));

  tmds_serializer green_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(sys_rst_pixel),
      .tmds_in(tmds_10b[1]),
      .tmds_out(tmds_signal[1]));

  tmds_serializer blue_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(sys_rst_pixel),
      .tmds_in(tmds_10b[0]),
      .tmds_out(tmds_signal[0]));

  // Output Buffers for HDMI Signals
  OBUFDS OBUFDS_red   (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
  OBUFDS OBUFDS_green (.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
  OBUFDS OBUFDS_blue  (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
  OBUFDS OBUFDS_clock (.I(clk_pixel),      .O(hdmi_clk_p),   .OB(hdmi_clk_n));

  // ** Camera Initialization over I2C (Unchanged) **

  logic  busy, bus_active;
  logic  cr_init_valid, cr_init_ready;

  logic  recent_reset;
  always_ff @(posedge clk_camera) begin
    if (sys_rst_camera) begin
      recent_reset <= 1'b1;
      cr_init_valid <= 1'b0;
    end
    else if (recent_reset) begin
      cr_init_valid <= 1'b1;
      recent_reset <= 1'b0;
    end else if (cr_init_valid && cr_init_ready) begin
      cr_init_valid <= 1'b0;
    end
  end

  logic [23:0] bram_dout;
  logic [7:0]  bram_addr;

  // ROM holding pre-built camera settings to send
  xilinx_single_port_ram_read_first
    #(
      .RAM_WIDTH(24),
      .RAM_DEPTH(256),
      .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
      .INIT_FILE("rom.mem")
    ) registers
    (
     .addra(bram_addr),
     .dina(24'b0),
     .clka(clk_camera),
     .wea(1'b0),
     .ena(1'b1),
     .rsta(sys_rst_camera),
     .regcea(1'b1),
     .douta(bram_dout)
    );

  logic [23:0] registers_dout;
  logic [7:0]  registers_addr;
  assign registers_dout = bram_dout;
  assign bram_addr = registers_addr;

  logic       con_scl_i, con_scl_o, con_scl_t;
  logic       con_sda_i, con_sda_o, con_sda_t;

  // IOBUFs for I2C signals
  IOBUF IOBUF_scl (.I(con_scl_o), .IO(i2c_scl), .O(con_scl_i), .T(con_scl_t) );
  IOBUF IOBUF_sda (.I(con_sda_o), .IO(i2c_sda), .O(con_sda_i), .T(con_sda_t) );

  // Camera Registers Module
  camera_registers crw
    (
     .clk_in(clk_camera),
     .rst_in(sys_rst_camera),
     .init_valid(cr_init_valid),
     .init_ready(cr_init_ready),
     .scl_i(con_scl_i),
     .scl_o(con_scl_o),
     .scl_t(con_scl_t),
     .sda_i(con_sda_i),
     .sda_o(con_sda_o),
     .sda_t(con_sda_t),
     .bram_dout(registers_dout),
     .bram_addr(registers_addr)
    );

  // ** LED Indicators **

  assign led[0] = crw.bus_active;
  assign led[1] = cr_init_valid;
  assign led[2] = cr_init_ready;
  assign led[15:3] = 0;

endmodule // top_level


`default_nettype wire
