`timescale 1ns / 1ps
`default_nettype none

module top_level
  (
   input wire          clk_100mhz,
   output logic [15:0] led,
   // camera bus
   input wire [7:0]    camera_d, // 8 parallel data wires
   output logic        cam_xclk, // XC driving camera
   input wire          cam_hsync, // camera hsync wire
   input wire          cam_vsync, // camera vsync wire
   input wire          cam_pclk, // camera pixel clock
   inout wire          i2c_scl, // i2c inout clock
   inout wire          i2c_sda, // i2c inout data
   input wire lidar_out_raw, 
   input wire [15:0]   sw,
   input wire [3:0]    btn,
   output logic [2:0]  rgb0,
   output logic [2:0]  rgb1,
   // seven segment
   output logic [3:0]  ss0_an,//anode control for upper four digits of seven-seg display
   output logic [3:0]  ss1_an,//anode control for lower four digits of seven-seg display
   output logic [6:0]  ss0_c, //cathode controls for the segments of upper four digits
   output logic [6:0]  ss1_c, //cathod controls for the segments of lower four digits
   // hdmi port
   output logic [2:0]  hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
   output logic [2:0]  hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
   output logic        hdmi_clk_p, hdmi_clk_n,
   output logic [3:0] servo //differential hdmi clock
   );
   //assign led = sw;

  // shut up those RGBs
  assign rgb0 = 0;
  assign rgb1 = 0;

  // Clock and Reset Signals
  logic          sys_rst_camera;
  logic          sys_rst_pixel;

  logic          clk_camera;
  logic          clk_pixel;
  logic          clk_5x;
  logic          clk_xc;

  logic          clk_100_passthrough;

  // clocking wizards to generate the clock speeds we need for our different domains
  // clk_camera: 200MHz, fast enough to comfortably sample the camera's PCLK (50MHz)
  logic clk_100mhz_buffered;

//   BUFG clk_100mhz_buf (
//   .I(clk_100mhz),   // Input clock
//   .O(clk_100mhz_buffered)  // Buffered clock output
// );

  cw_hdmi_clk_wiz wizard_hdmi
    (.sysclk(clk_100_passthrough),
     .clk_pixel(clk_pixel),
     .clk_tmds(clk_5x),
     .reset(0));

  cw_fast_clk_wiz wizard_migcam
    (.clk_in1(clk_100mhz),
     .clk_camera(clk_camera),
     .clk_xc(clk_xc),
     .clk_100(clk_100_passthrough),
     .reset(0));

  // assign camera's xclk to pmod port: drive the operating clock of the camera!
  // this port also is specifically set to high drive by the XDC file.
  assign cam_xclk = clk_xc;

  assign sys_rst_camera = btn[0]; //use for resetting camera side of logic
  assign sys_rst_pixel = btn[0]; //use for resetting hdmi/draw side of logic

  // video signal generator signals
  logic          hsync_hdmi;
  logic          vsync_hdmi;
  logic [10:0]   hcount_hdmi;
  logic [9:0]    vcount_hdmi;
  logic          active_draw_hdmi;
  logic          new_frame_hdmi;
  logic [5:0]    frame_count_hdmi;
  logic          nf_hdmi;

  // rgb output values
  //logic [7:0]          red,green,blue;

  // ** Handling input from the camera **

  // synchronizers to prevent metastability
  logic [7:0]    camera_d_buf [1:0];
  logic          cam_hsync_buf [1:0];
  logic          cam_vsync_buf [1:0];
  logic          cam_pclk_buf [1:0];

  always_ff @(posedge clk_camera) begin
     camera_d_buf <= {camera_d_buf[0], camera_d};
     cam_pclk_buf <= {cam_pclk_buf[0], cam_pclk};
     cam_hsync_buf <= {cam_hsync_buf[0], cam_hsync};
     cam_vsync_buf <= {cam_vsync_buf[0], cam_vsync};
  end

  logic [10:0] camera_hcount;
  logic [9:0]  camera_vcount;
  logic [15:0] camera_pixel;
  logic        camera_valid;

  // your pixel_reconstruct module, from the exercise!
  // hook it up to buffered inputs.
  pixel_reconstruct pixel_reconstruct_inst (
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

  // two-port BRAM used to hold image from camera.
  localparam FB_DEPTH = 320*180;
  localparam FB_SIZE = $clog2(FB_DEPTH);
  logic [FB_SIZE-1:0] addra; // used to specify address to write to in frame buffer

  logic valid_camera_mem; // used to enable writing pixel data to frame buffer
  logic [15:0] camera_mem; // used to pass pixel data into frame buffer

  // Camera write logic
  always_ff @(posedge clk_camera) begin
    if (camera_valid) begin
      if ((camera_hcount[1:0] == 2'b00) && (camera_vcount[1:0] == 2'b00)) begin // if divisible by 4
        // Downsample by 4 in both x and y
        addra <= (camera_hcount >> 2) + (320 * (camera_vcount >> 2));
        camera_mem <= camera_pixel;
        valid_camera_mem <= 1'b1;
      end else begin
        valid_camera_mem <= 1'b0;
      end
    end else begin
      valid_camera_mem <= 1'b0;
    end
  end

  // Frame buffer from IP
  blk_mem_gen_0 frame_buffer (
    .addra(addra),
    .clka(clk_camera),
    .wea(valid_camera_mem),
    .dina(camera_mem),
    .ena(1'b1),
    .douta(), // never read from this side
    .addrb(addrb),
    .dinb(16'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(1'b1),
    .doutb(frame_buff_raw)
  );

  logic [15:0] frame_buff_raw; // data out of frame buffer (565)
  logic [FB_SIZE-1:0] addrb; // used to lookup address in memory for reading from buffer
  logic good_addrb; // used to indicate within valid frame for scaling

  // Scaling logic
  logic [1:0] scale_factor; // 0 for 1X, 1 for 2X, 2 for 4X

  always_comb begin
    if (btn[1]) begin
      scale_factor = 2'd0; // 1X scaling
    end else if (sw[0] == 1'b0) begin
      scale_factor = 2'd1; // 2X scaling
    end else begin
      scale_factor = 2'd2; // 4X scaling
    end
  end

  logic [10:0] scaled_hcount;
  logic [9:0] scaled_vcount;

  always_ff @(posedge clk_pixel) begin
    // Calculate scaled hcount and vcount
    scaled_hcount <= hcount_hdmi >> scale_factor;
    scaled_vcount <= vcount_hdmi >> scale_factor;

    // Determine if the current hcount and vcount are within the displayable range
    case (scale_factor)
      2'd0: begin // 1X scaling
        good_addrb <= (hcount_hdmi < 320) && (vcount_hdmi < 180);
      end
      2'd1: begin // 2X scaling
        good_addrb <= (hcount_hdmi < 640) && (vcount_hdmi < 360);
      end
      2'd2: begin // 4X scaling
        good_addrb <= (hcount_hdmi < 1280) && (vcount_hdmi < 720);
      end
      default: good_addrb <= 1'b0;
    endcase

    // Calculate frame buffer address
    if (good_addrb) begin
      addrb <= scaled_hcount + 320 * scaled_vcount;
    end else begin
      addrb <= 0; // Default value when out of range
    end
  end

  // Split frame_buff into 3 8-bit color channels (5:6:5 adjusted accordingly)
  logic [7:0] fb_red, fb_green, fb_blue;
  always_ff @(posedge clk_pixel) begin
    fb_red <= good_addrb ? {frame_buff_raw[15:11],3'b0} : 8'b0;
    fb_green <= good_addrb ? {frame_buff_raw[10:5], 2'b0} : 8'b0;
    fb_blue <= good_addrb ? {frame_buff_raw[4:0],3'b0} : 8'b0;
  end

  // Delay fb_red, fb_green, fb_blue by 4 cycles before video_mux
  logic [7:0] fb_red_delayed [0:3];
  logic [7:0] fb_green_delayed [0:3];
  logic [7:0] fb_blue_delayed [0:3];

  always_ff @(posedge clk_pixel) begin
    fb_red_delayed[0] <= fb_red;
    fb_green_delayed[0] <= fb_green;
    fb_blue_delayed[0] <= fb_blue;

    for (int i = 0; i < 3; i++) begin
      fb_red_delayed[i+1] <= fb_red_delayed[i];
      fb_green_delayed[i+1] <= fb_green_delayed[i];
      fb_blue_delayed[i+1] <= fb_blue_delayed[i];
    end
  end

  // Pipeline stages for synchronization
  logic [10:0] hcount_hdmi_delayed [0:7];
  logic [9:0] vcount_hdmi_delayed [0:7];
  logic vsync_hdmi_delayed [0:7];
  logic hsync_hdmi_delayed [0:7];
  logic nf_hdmi_delayed [0:7];
  logic active_draw_hdmi_delayed [0:7];
  logic [5:0] frame_count_hdmi_delayed [0:7];

  always_ff @(posedge clk_pixel) begin
    hcount_hdmi_delayed[0] <= hcount_hdmi;
    vcount_hdmi_delayed[0] <= vcount_hdmi;
    vsync_hdmi_delayed[0] <= vsync_hdmi;
    hsync_hdmi_delayed[0] <= hsync_hdmi;
    nf_hdmi_delayed[0] <= nf_hdmi;
    active_draw_hdmi_delayed[0] <= active_draw_hdmi;
    frame_count_hdmi_delayed[0] <= frame_count_hdmi;

    for (int i = 0; i < 7; i++) begin
      hcount_hdmi_delayed[i+1] <= hcount_hdmi_delayed[i];
      vcount_hdmi_delayed[i+1] <= vcount_hdmi_delayed[i];
      vsync_hdmi_delayed[i+1] <= vsync_hdmi_delayed[i];
      hsync_hdmi_delayed[i+1] <= hsync_hdmi_delayed[i];
      nf_hdmi_delayed[i+1] <= nf_hdmi_delayed[i];
      active_draw_hdmi_delayed[i+1] <= active_draw_hdmi_delayed[i];
      frame_count_hdmi_delayed[i+1] <= frame_count_hdmi_delayed[i];
    end
  end

  // HDMI video signal generator
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

  // RGB to YCrCb
  logic [9:0] y_full, cr_full, cb_full; // ycrcb conversion of full pixel
  logic [7:0] y, cr, cb; // ycrcb conversion of full pixel

  rgb_to_ycrcb rgbtoycrcb_m(
    .clk_in(clk_pixel),
    .r_in(fb_red),
    .g_in(fb_green),
    .b_in(fb_blue),
    .y_out(y_full),
    .cr_out(cr_full),
    .cb_out(cb_full)
  );

  assign y = y_full[7:0];
  assign cr = {!cr_full[9], cr_full[8:1]};
  assign cb = {!cb_full[9], cb_full[8:1]};

  // Delay y by 1 cycle
  logic [7:0] y_delayed [0:1];

always_ff @(posedge clk_pixel) begin
    y_delayed[0] <= y;
    y_delayed [1] <= y_delayed [0];
  end

  // Channel select module
  logic [2:0] channel_sel;
  logic [7:0] selected_channel; // selected channels

  assign channel_sel = sw[3:1];

  channel_select mcs(
     .sel_in(channel_sel),
     .r_in(fb_red_delayed[2]),
     .g_in(fb_green_delayed[2]),
     .b_in(fb_blue_delayed[2]),
     .y_in(y),
     .cr_in(cr),
     .cb_in(cb),
     .channel_out(selected_channel)
  );

  // Delay selected_channel by 1 cycle
  logic [7:0] selected_channel_delayed;

  always_ff @(posedge clk_pixel) begin
    selected_channel_delayed <= selected_channel;
  end
  logic [7:0] lower_threshold;
  logic [7:0] upper_threshold;
  // Threshold values used to determine what value passes
  assign lower_threshold = {sw[11:8],4'b0};
  assign upper_threshold = {sw[15:12],4'b0};

  logic mask; // Whether or not thresholded pixel is 1 or 0

  threshold mt(
     .clk_in(clk_pixel),
     .rst_in(sys_rst_pixel),
     .pixel_in(selected_channel),
     .lower_bound_in(lower_threshold),
     .upper_bound_in(upper_threshold),
     .mask_out(mask)
  );

  parameter REFRESH_RATE = 100;

   logic uart_input;
   assign uart_input = lidar_out_raw;

   logic uart_rx_buf0, uart_rx_buf1;
   logic new_uart_out;
   logic [7:0] data_uart_out;
   logic [3:0] frame_cnt;

  //different frame values
   logic [7:0] frame1_data; //should be 0x59
   logic [7:0] frame2_data;//should be 0x59
   logic [15:0] distance; //bit #2 + #3
   logic [15:0] distance_buf;
   logic [15:0] strength;
   logic [15:0] temperature;
   logic [7:0] checksum;



    always_ff@(posedge clk_100_passthrough) begin
     uart_rx_buf0<=uart_input;
     uart_rx_buf1<=uart_rx_buf0;
     distance_buf<=distance;
    if(new_uart_out==1 && frame_cnt==0) begin
        frame1_data<={8'b0, data_uart_out}; 
    end else if(new_uart_out==1 && frame_cnt == 1) begin
        frame2_data<={8'b0, data_uart_out}; 
    end else if(new_uart_out==1 && frame_cnt==2) begin
      distance<={8'b0, data_uart_out}; 
    end else if (new_uart_out==1 && frame_cnt==3) begin
      distance<={data_uart_out, distance[7:0]}; 
    end else if(new_uart_out==1 && frame_cnt==4) begin
      strength<={8'b0, data_uart_out}; 
    end else if (new_uart_out==1 && frame_cnt==5) begin
      strength<={data_uart_out, strength[7:0]}; 
    end else if(new_uart_out==1 && frame_cnt==6) begin
      temperature<={8'b0, data_uart_out}; 
    end else if (new_uart_out==1 && frame_cnt==7) begin
      temperature<={data_uart_out, temperature[7:0]}; 
    end else if (new_uart_out==1 && frame_cnt==8) begin
      checksum<={data_uart_out, temperature[7:0]}; 
    end
    end
    // UART Receiver
    // TODO: instantiate your uart_receive module, connected up to the buffered uart_rx signal
     // declare any signals you need to keep track of!
    logic rst_frame_cnt;
    assign rst_frame_cnt = btn[3];
    uart_lidar_receive
    #(   .INPUT_CLOCK_FREQ(100000000),
         .BAUD_RATE(115200)
    )uart_r
     ( .clk_in(clk_100_passthrough),
       .rst_in(sys_rst_camera),
       .rx_wire_in(uart_rx_buf1),
       .rst_frame_cnt(rst_frame_cnt),
       .new_data_out(new_uart_out),
       .data_byte_out(data_uart_out),
       .frame_counter(frame_cnt)
      );
   //shut up those rgb LEDs for now (active high):
   assign rgb1 = 0; //set to 0.
   assign rgb0 = 0; //set to 0.


   logic [31:0] val_to_display; //either the spi data or the btn_count data (default)
   //logic [6:0] ss_c; //used to grab output cathode signal for 7s leds
   logic[$clog2(REFRESH_RATE)-1:0]  count_out; 
   evt_counter #(.MAX_COUNT(REFRESH_RATE)) msc(.clk_in(clk_100_passthrough),
   .rst_in(sys_rst_camera),
   .evt_in((new_uart_out==1 && frame_cnt == 2)),
   .count_out(count_out));
   
   always_ff@(posedge clk_100_passthrough) begin
    if (count_out==0) begin
      val_to_display <= {strength, distance};
    end
   end


   localparam CYCLES_PER_TRIGGER = 12500; // MUST CHANGE - D

   logic [31:0]        trigger_count;
   logic               spi_trigger;

  //  counter counter_8khz_trigger
  //    (.clk_in(clk_100mhz),
  //     .rst_in(sys_rst),
  //     .period_in(CYCLES_PER_TRIGGER),
  //     .count_out(trigger_count));

  //assign val_to_display = {24'b0, 8'b11110011};

    // seven_segment_controller ssc(.clk_in(clk_100mhz),
    // .rst_in(sys_rst),
    // .val_in(val_to_display),
    // .cat_out(ss_c),
    // .an_out({ss0_an, ss1_an}));

    // assign ss0_c = ss_c; //control upper four digit's cathodes!
    // assign ss1_c = ss_c; //same as above but for lower four digits!

    //Binary to decimal conversion

    logic [19:0] bcd_distance;
    bin_to_dec #(
      .INPUT_WIDTH(16),
      .DECIMAL_DIGITS(5)
    )bin2dec(
      .binary_in(distance_buf),
      .bcd_out(bcd_distance)
    );



  // Delay mask to match pipeline stages (delayed by 5 cycles)
  //logic mask_delayed [0:5];

  //always_ff @(posedge clk_pixel) begin
  //  mask_delayed[0] <= mask;
    //for (int i = 0; i < 5; i++) begin
      //mask_delayed[i+1] <= mask_delayed[i];
    //end
  //end

  // Center of Mass Calculation
  logic [10:0] x_com, x_com_calc; // long term x_com and output from module, resp
  logic [9:0] y_com, y_com_calc; // long term y_com and output from module, resp
  logic new_com; // used to know when to update x_com and y_com ...

  always_ff @(posedge clk_pixel) begin
    if (sys_rst_pixel) begin
      x_com <= 0;
      y_com <= 0;
    end else if (new_com) begin
      x_com <= x_com_calc;
      y_com <= y_com_calc;
    end
  end

  center_of_mass com_m(
    .clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .x_in(hcount_hdmi_delayed[7]),
    .y_in(vcount_hdmi_delayed[7]),
    .valid_in(mask),
    .tabulate_in(nf_hdmi),
    .x_out(x_com_calc),
    .y_out(y_com_calc),
    .valid_out(new_com)
  );

  // Seven segment display
  logic [6:0] ss_c;

  // lab05_ssc mssc(.clk_in(clk_pixel),
  //                .rst_in(sys_rst_pixel),
  //                .lt_in(lower_threshold),
  //                .ut_in(upper_threshold),
  //                .channel_sel_in(channel_sel),
  //                .cat_out(ss_c),
  //                .an_out({ss0_an, ss1_an})
  // );
  seven_segment_controller ssc
  (.clk_in(clk_pixel),
   .rst_in(sys_rst_pixel),
   .val_in({frame1_data,distance_buf}),
   .cat_out(ss_c),
   .an_out({ss0_an, ss1_an})
  );
  assign ss0_c = ss_c; // control upper four digit's cathodes
  assign ss1_c = ss_c; // same as above but for lower four digits

  // Crosshair output
  logic [7:0] ch_red, ch_green, ch_blue;

  always_comb begin
    ch_red   = ((vcount_hdmi_delayed [7] == y_com) || (hcount_hdmi_delayed [7] == x_com)) ? 8'hFF : 8'h00;
    ch_green = ((vcount_hdmi_delayed[7] == y_com) || (hcount_hdmi_delayed [7] == x_com)) ? 8'hFF : 8'h00;
    ch_blue  = ((vcount_hdmi_delayed [7] == y_com) || (hcount_hdmi_delayed [7] == x_com)) ? 8'hFF : 8'h00;
  end

  // Delay ch_red, ch_green, ch_blue by 8 cycles before video_mux
  logic [7:0] ch_red_delayed [0:7];
  logic [7:0] ch_green_delayed [0:7];
  logic [7:0] ch_blue_delayed [0:7];

  always_ff @(posedge clk_pixel) begin
    ch_red_delayed[0] <= ch_red;
    ch_green_delayed[0] <= ch_green;
    ch_blue_delayed[0] <= ch_blue;

    for (int i = 0; i < 7; i++) begin
      ch_red_delayed[i+1] <= ch_red_delayed[i];
      ch_green_delayed[i+1] <= ch_green_delayed[i];
      ch_blue_delayed[i+1] <= ch_blue_delayed[i];
    end
  end

  // Image sprite output
  logic [7:0] img_red, img_green, img_blue;

  // Adjust x_com and y_com boundaries
  logic [10:0] x_com_bound;
  logic [9:0] y_com_bound;

  always_comb begin
    if (y_com >= (720 - 128)) begin
      y_com_bound = y_com - 128;
    end else if (y_com <= 256) begin
      y_com_bound = 128;
    end else begin
      y_com_bound = y_com;
    end

    if (x_com >= (1280 - 128)) begin
      x_com_bound = x_com - 128;
    end else if (x_com <= 128) begin
      x_com_bound = 128;
    end else begin
      x_com_bound = x_com;
    end
  end

  // Instantiate image_sprite module
  // image_sprite sprite_inst (
  //   .pixel_clk_in(clk_pixel),
  //   .rst_in(sys_rst_pixel),
  //   .x_in(x_com_bound - 128),
  //   .y_in(y_com_bound - 128),
  //   .hcount_in(hcount_hdmi), // Direct from video_sig_gen
  //   .vcount_in(vcount_hdmi), // Direct from video_sig_gen
  //   .red_out(img_red),
  //   .green_out(img_green),
  //   .blue_out(img_blue)
  // );
  // Image sprite RGB outputs
  logic [7:0] img_red0, img_green0, img_blue0;
  logic [7:0] img_red1, img_green1, img_blue1;
  logic [7:0] img_red2, img_green2, img_blue2;
  logic [7:0] img_red3, img_green3, img_blue3;
  logic [7:0] img_red4, img_green4, img_blue4;


  image_digit
  #(
  .WIDTH(100),
  .HEIGHT(100)) 
  digit4_inst (
    .pixel_clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .x_in(10),
    .y_in(10),
    .digit(bcd_distance[19:16]),//(sw[15:12]),
    .hcount_in(hcount_hdmi), // Direct from video_sig_gen
    .vcount_in(vcount_hdmi), // Direct from video_sig_gen
    .red_out(img_red4),
    .green_out(img_green4),
    .blue_out(img_blue4)
  );
image_digit
  #(
  .WIDTH(100),
  .HEIGHT(100)) 
  digit3_inst (
    .pixel_clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .x_in(110),
    .y_in(10),
    .digit(bcd_distance[15:12]),//(sw[15:12]),
    .hcount_in(hcount_hdmi), // Direct from video_sig_gen
    .vcount_in(vcount_hdmi), // Direct from video_sig_gen
    .red_out(img_red3),
    .green_out(img_green3),
    .blue_out(img_blue3)
  );
image_digit
  #(
  .WIDTH(100),
  .HEIGHT(100)) 
  digit2_inst (
    .pixel_clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .x_in(210),
    .y_in(10),
    .digit(bcd_distance[11:8]),//(sw[15:12]),
    .hcount_in(hcount_hdmi), // Direct from video_sig_gen
    .vcount_in(vcount_hdmi), // Direct from video_sig_gen
    .red_out(img_red2),
    .green_out(img_green2),
    .blue_out(img_blue2)
  );
  image_digit
  #(
  .WIDTH(100),
  .HEIGHT(100)) 
  digit1_inst (
    .pixel_clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .x_in(310),
    .y_in(10),
    .digit(bcd_distance[7:4]),//(sw[15:12]),
    .hcount_in(hcount_hdmi), // Direct from video_sig_gen
    .vcount_in(vcount_hdmi), // Direct from video_sig_gen
    .red_out(img_red1),
    .green_out(img_green1),
    .blue_out(img_blue1)
  );
  image_digit
  #(
  .WIDTH(100),
  .HEIGHT(100)) 
  digit0_inst (
    .pixel_clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .x_in(410),
    .y_in(10),
    .digit(bcd_distance[3:0]),
    .hcount_in(hcount_hdmi), // Direct from video_sig_gen
    .vcount_in(vcount_hdmi), // Direct from video_sig_gen
    .red_out(img_red0),
    .green_out(img_green0),
    .blue_out(img_blue0)
  );

  logic [7:0] red, green, blue;
  always_comb begin
    img_red = img_red0|img_red1|img_red2|img_red3|img_red4;
    img_green = img_green0|img_green1|img_green2|img_green3|img_green4;
    img_blue = img_blue0|img_blue1|img_blue2|img_blue3|img_blue4;
  end




  // Delay img_red, img_green, img_blue by 4 cycles before video_mux
  logic [7:0] img_red_delayed [0:4];
  logic [7:0] img_green_delayed [0:4];
  logic [7:0] img_blue_delayed [0:4];

  always_ff @(posedge clk_pixel) begin
    img_red_delayed[0] <= img_red;
    img_green_delayed[0] <= img_green;
    img_blue_delayed[0] <= img_blue;

    for (int i = 0; i < 4; i++) begin
      img_red_delayed[i+1] <= img_red_delayed[i];
      img_green_delayed[i+1] <= img_green_delayed[i];
      img_blue_delayed[i+1] <= img_blue_delayed[i];
    end
  end

  // Video Mux: select from the different display modes based on switch values
  logic [1:0] display_choice;
  logic [1:0] target_choice;

  assign display_choice = sw[5:4];
  assign target_choice =  sw[7:6];

  video_mux mvm(
    .bg_in(display_choice), // choose background
    .target_in(target_choice), // choose target
    .camera_pixel_in({fb_red_delayed[3], fb_green_delayed[3], fb_blue_delayed[3]}),
    .camera_y_in(y_delayed [0]),
    .channel_in(selected_channel_delayed),
    .thresholded_pixel_in(mask),
    .crosshair_in({ch_red_delayed[7], ch_green_delayed[7], ch_blue_delayed[7]}),
    .com_sprite_pixel_in({img_red_delayed[3], img_green_delayed[3], img_blue_delayed[3]}),
    .pixel_out({red,green,blue})
  );

  // TMDS encoders
  logic [9:0] tmds_10b [0:2]; // output of each TMDS encoder
  logic       tmds_signal [0:2]; // output of each TMDS serializer

  tmds_encoder tmds_red(
      .clk_in(clk_pixel),
      .rst_in(sys_rst_pixel),
      .data_in(red),
      .control_in(2'b0),
      .ve_in(active_draw_hdmi_delayed [7]),
      .tmds_out(tmds_10b[2]));

  tmds_encoder tmds_green(
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .data_in(green),
        .control_in(2'b0),
        .ve_in(active_draw_hdmi_delayed [7]),
        .tmds_out(tmds_10b[1]));

  tmds_encoder tmds_blue(
       .clk_in(clk_pixel),
       .rst_in(sys_rst_pixel),
       .data_in(blue),
       .control_in({vsync_hdmi_delayed [7], hsync_hdmi_delayed [7]}),
       .ve_in(active_draw_hdmi_delayed [7]),
       .tmds_out(tmds_10b[0]));

  // TMDS serializers
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


   //output buffers generating differential signals:
   //three for the r,g,b signals and one that is at the pixel clock rate
   //the HDMI receivers use recover logic coupled with the control signals asserted
   //during blanking and sync periods to synchronize their faster bit clocks off
   //of the slower pixel clock (so they can recover a clock of about 742.5 MHz from
   //the slower 74.25 MHz clock)
   OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
   OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
   OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
   OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));


   // Nothing To Touch Down Here:
   // register writes to the camera

   // The OV5640 has an I2C bus connected to the board, which is used
   // for setting all the hardware settings (gain, white balance,
   // compression, image quality, etc) needed to start the camera up.
   // We've taken care of setting these all these values for you:
   // "rom.mem" holds a sequence of bytes to be sent over I2C to get
   // the camera up and running, and we've written a design that sends
   // them just after a reset completes.

   // If the camera is not giving data, press your reset button.

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
        .addra(bram_addr),     // Address bus, width determined from RAM_DEPTH
        .dina(24'b0),          // RAM input data, width determined from RAM_WIDTH
        .clka(clk_camera),     // Clock
        .wea(1'b0),            // Write enable
        .ena(1'b1),            // RAM Enable, for additional power savings, disable port when not in use
        .rsta(sys_rst_camera), // Output reset (does not affect memory contents)
        .regcea(1'b1),         // Output register enable
        .douta(bram_dout)      // RAM output data, width determined from RAM_WIDTH
        );

   logic [23:0] registers_dout;
   logic [7:0]  registers_addr;
   assign registers_dout = bram_dout;
   assign bram_addr = registers_addr;

   logic       con_scl_i, con_scl_o, con_scl_t;
   logic       con_sda_i, con_sda_o, con_sda_t;

   // NOTE these also have pullup specified in the xdc file!
   // access our inouts properly as tri-state pins
   IOBUF IOBUF_scl (.I(con_scl_o), .IO(i2c_scl), .O(con_scl_i), .T(con_scl_t) );
   IOBUF IOBUF_sda (.I(con_sda_o), .IO(i2c_sda), .O(con_sda_i), .T(con_sda_t) );

   // provided module to send data BRAM -> I2C
   camera_registers crw
     (.clk_in(clk_camera),
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
      .bram_addr(registers_addr));

   // a handful of debug signals for writing to registers
   assign led[0] = crw.bus_active;
   assign led[1] = cr_init_valid;
   assign led[2] = cr_init_ready;
   assign led[15:3] = 0;


   add_to_top_level servo
   (.servo(servo));
endmodule // top_level


`default_nettype wire