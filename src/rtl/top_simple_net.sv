// top_simple_net.sv
// Top-level integration for Simple-Net FPGA Object Detection
//
// Data flow:
//   Camera -> cam_to_ddr3 -> DDR3 -> ddr3_to_display -> bbox_overlay -> HDMI
//        └-> downsample_128 -> [async FIFO CDC] -> cnn_pipeline -> detect (x,y,conf)
//
// Clock domains:
//   sys_clk    100 MHz  — input oscillator
//   clk_24mhz   24 MHz  — camera XCLK + SCCB
//   clk_25mhz   25 MHz  — HDMI pixel clock
//   clk_125mhz 125 MHz  — HDMI serializer (5x pixel)
//   ui_clk      ~83 MHz — MIG DDR3 controller + CNN pipeline
//   cam_pclk    ~12 MHz — camera pixel clock (from OV7670)
//
// Clock domain crossings:
//   cam_pclk -> ui_clk:    async_fifo in cam_to_ddr3 (camera writes)
//   cam_pclk -> ui_clk:    async_fifo for downsampler->CNN path
//   ui_clk   -> clk_25mhz: double-FF sync for detection results
//   cam_pclk -> ui_clk:    double-FF sync for frame_start

module top_simple_net (
    // System
    input sys_clk,              // 100 MHz board oscillator
    output logic [3:0] debug_led, // Debug LEDs

    // OV7670 Camera
    input  [7:0] cam_data,      // 8-bit parallel pixel data
    input        cam_pclk,      // Pixel clock from camera
    output logic cam_xclk,      // 24 MHz clock to camera
    input        cam_vsync,     // Vertical sync
    input        cam_href,      // Horizontal reference
    inout        cam_siod,      // SCCB data (I2C-like, bidirectional)
    output logic cam_sioc,      // SCCB clock

    // HDMI Output
    output logic hdmi_clk_p,
    output logic hdmi_clk_n,
    output logic hdmi_d0_p,
    output logic hdmi_d0_n,
    output logic hdmi_d1_p,
    output logic hdmi_d1_n,
    output logic hdmi_d2_p,
    output logic hdmi_d2_n,

    // DDR3 Memory (directly to MIG IP — MIG generates constraints)
    output [13:0] ddr3_addr,
    output [2:0]  ddr3_ba,
    output        ddr3_cas_n,
    output        ddr3_ck_n,
    output        ddr3_ck_p,
    output        ddr3_cke,
    output        ddr3_ras_n,
    output        ddr3_reset_n,
    output        ddr3_we_n,
    inout  [15:0] ddr3_dq,
    inout  [1:0]  ddr3_dqs_n,
    inout  [1:0]  ddr3_dqs_p,
    output        ddr3_cs_n,
    output [1:0]  ddr3_dm,
    output        ddr3_odt
);

    // CONSTANTS
    localparam [27:0] FB0_BASE = 28'h000_0000;
    localparam [27:0] FB1_BASE = 28'h010_0000;
    localparam [27:0] CNN_BASE = 28'h020_0000;
    localparam [13:0] CNN_PIXEL_COUNT = 14'd16384;  // 128x128

    // SECTION 1: Clock Generation
    logic clk_24mhz, clk_25mhz, clk_125mhz;
    logic rst_24mhz, rst_25mhz, rst_125mhz;
    logic clk_locked;

    clk_generator u_clk_gen (
        .sys_clk    (sys_clk),
        .clk_24mhz  (clk_24mhz),
        .clk_25mhz  (clk_25mhz),
        .clk_125mhz (clk_125mhz),
        .rst_24mhz  (rst_24mhz),
        .rst_25mhz  (rst_25mhz),
        .rst_125mhz (rst_125mhz),
        .locked      (clk_locked)
    );

    // Camera XCLK: 24 MHz output to OV7670
    assign cam_xclk = clk_24mhz;

    // SECTION 2: MIG DDR3 Controller
    logic        ui_clk;
    logic        ui_rst;
    logic        calib_complete;

    // MIG application interface
    logic [27:0]  mig_app_addr;
    logic [2:0]   mig_app_cmd;
    logic         mig_app_en;
    logic         mig_app_rdy;
    logic [127:0] mig_app_wdf_data;
    logic [15:0]  mig_app_wdf_mask;
    logic         mig_app_wdf_wren;
    logic         mig_app_wdf_end;
    logic         mig_app_wdf_rdy;
    logic [127:0] mig_app_rd_data;
    logic         mig_app_rd_data_valid;
    logic         mig_app_rd_data_end;

    // MIG IP instantiation
    // NOTE: Generate this IP using Vivado MIG wizard for your board.
    //       The instance name must match what the wizard creates.
    //       Configure for: DDR3L, 16-bit, 128-bit UI, ~83 MHz UI clock
    mig_7series_0 u_mig (
        // DDR3 physical pins
        .ddr3_addr          (ddr3_addr),
        .ddr3_ba            (ddr3_ba),
        .ddr3_cas_n         (ddr3_cas_n),
        .ddr3_ck_n          (ddr3_ck_n),
        .ddr3_ck_p          (ddr3_ck_p),
        .ddr3_cke           (ddr3_cke),
        .ddr3_ras_n         (ddr3_ras_n),
        .ddr3_reset_n       (ddr3_reset_n),
        .ddr3_we_n          (ddr3_we_n),
        .ddr3_dq            (ddr3_dq),
        .ddr3_dqs_n         (ddr3_dqs_n),
        .ddr3_dqs_p         (ddr3_dqs_p),
        .ddr3_cs_n          (ddr3_cs_n),
        .ddr3_dm            (ddr3_dm),
        .ddr3_odt           (ddr3_odt),
        // Application interface
        .app_addr           (mig_app_addr),
        .app_cmd            (mig_app_cmd),
        .app_en             (mig_app_en),
        .app_rdy            (mig_app_rdy),
        .app_wdf_data       (mig_app_wdf_data),
        .app_wdf_mask       (mig_app_wdf_mask),
        .app_wdf_wren       (mig_app_wdf_wren),
        .app_wdf_end        (mig_app_wdf_end),
        .app_wdf_rdy        (mig_app_wdf_rdy),
        .app_rd_data        (mig_app_rd_data),
        .app_rd_data_valid  (mig_app_rd_data_valid),
        .app_rd_data_end    (mig_app_rd_data_end),
        // System
        .sys_clk_i          (sys_clk),
        .sys_rst            (clk_locked),     // MIG reset is active-low on some configs
        .ui_clk             (ui_clk),
        .ui_clk_sync_rst    (ui_rst),
        .init_calib_complete (calib_complete)
    );

    // SECTION 3: Camera Reset Synchronization
    // cam_pclk comes from the OV7670 — we need a reset synchronized
    // to this domain. Use clk_locked inverted as async reset source.
    logic rst_pclk;

    reset_sync u_rst_pclk (
        .clk     (cam_pclk),
        .rst_in  (~clk_locked),
        .rst_out (rst_pclk)
    );

    // SECTION 4: Camera SCCB Configuration (I2C-like)
    // The OV7670 must be configured via SCCB before it outputs video.
    // ov7670_registers sequences through the register writes.
    // ov7670_sccb handles the 2-wire protocol.
    //
    // NOTE: These module interfaces are assumed based on standard
    // OV7670 FPGA implementations. Verify against your actual
    // ov7670_sccb.sv and ov7670_registers.sv files.

    logic        sccb_start;
    logic        sccb_done;
    logic [7:0]  sccb_reg_addr;
    logic [7:0]  sccb_reg_data;
    logic        sccb_reg_valid;
    logic        sccb_reg_done;
    logic        sccb_siod_oe;
    logic        sccb_siod_out;

    // Tristate handling for SCCB data line (open-drain)
    // When oe=1, drive low; when oe=0, release (pull-up provides high)
    assign cam_siod = sccb_siod_oe ? sccb_siod_out : 1'bz;

    // Start configuration after clocks are stable
    logic [23:0] sccb_delay_cnt;
    logic        sccb_cfg_start;

    always_ff @(posedge clk_24mhz) begin
        if (rst_24mhz) begin
            sccb_delay_cnt <= 24'd0;
            sccb_cfg_start <= 1'b0;
        end else begin
            // Wait ~100ms after reset before configuring camera
            // 24 MHz * 0.1s = 2,400,000 cycles
            if (sccb_delay_cnt < 24'd2_400_000) begin
                sccb_delay_cnt <= sccb_delay_cnt + 24'd1;
                sccb_cfg_start <= 1'b0;
            end else begin
                sccb_cfg_start <= 1'b1;
            end
        end
    end

    ov7670_registers u_cam_regs (
        .clk       (clk_24mhz),
        .rst       (rst_24mhz),
        .start     (sccb_cfg_start),
        .done      (),                  // Not used at top level
        .reg_addr  (sccb_reg_addr),
        .reg_data  (sccb_reg_data),
        .reg_valid (sccb_reg_valid),
        .reg_done  (sccb_reg_done)
    );

    ov7670_sccb u_sccb (
        .clk         (clk_24mhz),
        .rst         (rst_24mhz),
        .device_addr (8'h42),           // OV7670 write address
        .reg_addr    (sccb_reg_addr),
        .reg_data    (sccb_reg_data),
        .start       (sccb_reg_valid),
        .done        (sccb_reg_done),
        .sioc        (cam_sioc),
        .siod_oe     (sccb_siod_oe),
        .siod_out    (sccb_siod_out),
        .siod_in     (cam_siod)
    );

    // SECTION 5: Camera Pixel Capture
    logic [15:0] cap_pixel_data;
    logic        cap_pixel_valid;
    logic [18:0] cap_pixel_addr;    // Not used (cam_to_ddr3 computes own)
    logic        cap_frame_start;
    logic        cap_frame_done;

    ov7670_capture u_capture (
        .pclk        (cam_pclk),
        .rst         (rst_pclk),
        .vsync       (cam_vsync),
        .href        (cam_href),
        .d           (cam_data),
        .pixel_data  (cap_pixel_data),
        .pixel_valid (cap_pixel_valid),
        .pixel_addr  (cap_pixel_addr),
        .frame_start (cap_frame_start),
        .frame_done  (cap_frame_done)
    );

    // SECTION 6: Pixel Position Tracking
    // The downsampler needs (col, row) coordinates.
    // We derive these from the pixel stream using counters
    // rather than modifying ov7670_capture.

    logic [9:0] pix_col;
    logic [8:0] pix_row;

    always_ff @(posedge cam_pclk) begin
        if (rst_pclk) begin
            pix_col <= 10'd0;
            pix_row <= 9'd0;
        end else begin
            if (cap_frame_start) begin
                pix_col <= 10'd0;
                pix_row <= 9'd0;
            end else if (cap_pixel_valid) begin
                if (pix_col == 10'd639) begin
                    pix_col <= 10'd0;
                    pix_row <= pix_row + 9'd1;
                end else begin
                    pix_col <= pix_col + 10'd1;
                end
            end
        end
    end

    // SECTION 7: Double-Buffer Frame Selection
    // Simple toggle: camera writes to one buffer while display
    // reads from the other. Swap on each camera frame boundary.

    logic write_buf_sel;        // 0 = write FB0, 1 = write FB1
    logic [27:0] cam_fb_base;
    logic [27:0] disp_fb_base;

    // Sync frame_start to ui_clk for buffer swap
    logic frame_start_sync1, frame_start_sync2, frame_start_sync3;
    logic frame_start_ui_edge;

    always_ff @(posedge ui_clk) begin
        if (ui_rst) begin
            frame_start_sync1 <= 1'b0;
            frame_start_sync2 <= 1'b0;
            frame_start_sync3 <= 1'b0;
        end else begin
            frame_start_sync1 <= cap_frame_start;
            frame_start_sync2 <= frame_start_sync1;
            frame_start_sync3 <= frame_start_sync2;
        end
    end

    assign frame_start_ui_edge = frame_start_sync2 && !frame_start_sync3;

    always_ff @(posedge ui_clk) begin
        if (ui_rst) begin
            write_buf_sel <= 1'b0;
        end else if (frame_start_ui_edge) begin
            write_buf_sel <= ~write_buf_sel;
        end
    end

    assign cam_fb_base  = write_buf_sel ? FB1_BASE : FB0_BASE;
    assign disp_fb_base = write_buf_sel ? FB0_BASE : FB1_BASE;

    // SECTION 8: Camera -> DDR3 Write Path
    logic        cam_wr_req;
    logic [27:0] cam_wr_addr;
    logic [127:0] cam_wr_data;
    logic        cam_wr_ack;

    cam_to_ddr3 u_cam_to_ddr3 (
        .pclk         (cam_pclk),
        .pclk_rst     (rst_pclk),
        .pixel_data   (cap_pixel_data),
        .pixel_valid  (cap_pixel_valid),
        .frame_start  (cap_frame_start),
        .ui_clk       (ui_clk),
        .ui_rst       (ui_rst),
        .cam_wr_req   (cam_wr_req),
        .cam_wr_addr  (cam_wr_addr),
        .cam_wr_data  (cam_wr_data),
        .cam_wr_ack   (cam_wr_ack),
        .fb_base_addr (cam_fb_base)
    );

    // SECTION 9: Downsampler (640x480 -> 128x128 grayscale)
    // Runs in cam_pclk domain, watches the pixel stream,
    // picks nearest-neighbor samples and converts to grayscale.

    logic [7:0]  ds_pixel_data;
    logic        ds_pixel_valid;
    logic [13:0] ds_pixel_addr;

    downsample_128 u_downsample (
        .pclk          (cam_pclk),
        .rst           (rst_pclk),
        .pixel_data    (cap_pixel_data),
        .pixel_valid   (cap_pixel_valid),
        .pixel_col     (pix_col),
        .pixel_row     (pix_row),
        .frame_start   (cap_frame_start),
        .ds_pixel_data (ds_pixel_data),
        .ds_pixel_valid(ds_pixel_valid),
        .ds_pixel_addr (ds_pixel_addr)
    );

    // SECTION 10: Downsampler -> CNN Clock Domain Crossing
    // Async FIFO bridges cam_pclk -> ui_clk for CNN input.
    // Each entry: {14-bit addr, 8-bit pixel} = 22 bits

    logic        ds_fifo_wr_en;
    logic [21:0] ds_fifo_wr_data;
    logic        ds_fifo_full;
    logic        ds_fifo_rd_en;
    logic [21:0] ds_fifo_rd_data;
    logic        ds_fifo_empty;

    assign ds_fifo_wr_en   = ds_pixel_valid && !ds_fifo_full;
    assign ds_fifo_wr_data = {ds_pixel_addr, ds_pixel_data};

    async_fifo #(
        .DATA_WIDTH (22),
        .ADDR_WIDTH (4)         // 16-entry FIFO
    ) u_ds_fifo (
        .wr_clk   (cam_pclk),
        .wr_rst   (rst_pclk),
        .wr_en    (ds_fifo_wr_en),
        .wr_data  (ds_fifo_wr_data),
        .wr_full  (ds_fifo_full),
        .rd_clk   (ui_clk),
        .rd_rst   (ui_rst),
        .rd_en    (ds_fifo_rd_en),
        .rd_data  (ds_fifo_rd_data),
        .rd_empty (ds_fifo_empty)
    );

    // SECTION 11: CNN Input Loader (ui_clk domain)
    // Pops pixels from the async FIFO, feeds them into
    // cnn_pipeline's input port, counts pixels, and asserts
    // input_done when all 16384 pixels have been loaded.

    logic        cnn_input_valid;
    logic [7:0]  cnn_input_pixel;
    logic [13:0] cnn_input_addr;
    logic        cnn_input_done;
    logic        cnn_start;

    // Pixel counter
    logic [13:0] cnn_pixel_count;
    logic        cnn_frame_loaded;

    // Loader FSM
    typedef enum logic [1:0] {
        CNN_LOAD_IDLE,
        CNN_LOAD_READ,
        CNN_LOAD_FEED,
        CNN_LOAD_DONE
    } cnn_load_state_t;

    cnn_load_state_t cnn_load_state;

    // Sync frame_start into ui_clk domain for frame reset
    // (reuse frame_start_ui_edge from Section 7)

    always_ff @(posedge ui_clk) begin
        if (ui_rst) begin
            cnn_load_state  <= CNN_LOAD_IDLE;
            cnn_input_valid <= 1'b0;
            cnn_input_done  <= 1'b0;
            cnn_pixel_count <= 14'd0;
            cnn_frame_loaded <= 1'b0;
            ds_fifo_rd_en   <= 1'b0;
        end else begin
            cnn_input_valid <= 1'b0;
            ds_fifo_rd_en   <= 1'b0;

            // Reset on new frame
            if (frame_start_ui_edge) begin
                cnn_pixel_count  <= 14'd0;
                cnn_frame_loaded <= 1'b0;
                cnn_input_done   <= 1'b0;
                cnn_load_state   <= CNN_LOAD_IDLE;
            end

            case (cnn_load_state)
                CNN_LOAD_IDLE: begin
                    if (!ds_fifo_empty && !cnn_frame_loaded) begin
                        ds_fifo_rd_en <= 1'b1;
                        cnn_load_state <= CNN_LOAD_READ;
                    end
                end

                CNN_LOAD_READ: begin
                    // One cycle latency for FIFO read data
                    cnn_load_state <= CNN_LOAD_FEED;
                end

                CNN_LOAD_FEED: begin
                    cnn_input_addr  <= ds_fifo_rd_data[21:8];
                    cnn_input_pixel <= ds_fifo_rd_data[7:0];
                    cnn_input_valid <= 1'b1;
                    cnn_pixel_count <= cnn_pixel_count + 14'd1;

                    if (cnn_pixel_count == CNN_PIXEL_COUNT - 1) begin
                        cnn_frame_loaded <= 1'b1;
                        cnn_input_done   <= 1'b1;
                        cnn_load_state   <= CNN_LOAD_DONE;
                    end else begin
                        cnn_load_state <= CNN_LOAD_IDLE;
                    end
                end

                CNN_LOAD_DONE: begin
                    // Stay here until next frame resets us
                    cnn_input_done <= 1'b1;
                end
            endcase
        end
    end

    // SECTION 12: CNN Pipeline
    logic        cnn_busy;
    logic        cnn_done;
    logic [9:0]  cnn_detect_x;
    logic [9:0]  cnn_detect_y;
    logic [7:0]  cnn_detect_conf;

    cnn_pipeline u_cnn (
        .clk         (ui_clk),
        .rst         (ui_rst),
        .input_valid (cnn_input_valid),
        .input_pixel (cnn_input_pixel),
        .input_addr  (cnn_input_addr),
        .input_done  (cnn_input_done),
        .start       (cnn_start),
        .busy        (cnn_busy),
        .done        (cnn_done),
        .detect_x    (cnn_detect_x),
        .detect_y    (cnn_detect_y),
        .detect_conf (cnn_detect_conf)
    );

    // SECTION 13: CNN Inference Control (ui_clk domain)
    // Start inference once input is loaded.
    // Latch results and hold until next frame.

    logic        detect_valid_ui;
    logic [9:0]  detect_x_ui;
    logic [9:0]  detect_y_ui;
    logic [7:0]  detect_conf_ui;

    typedef enum logic [1:0] {
        INF_IDLE,
        INF_START,
        INF_RUNNING,
        INF_DONE
    } inf_state_t;

    inf_state_t inf_state;

    always_ff @(posedge ui_clk) begin
        if (ui_rst) begin
            inf_state      <= INF_IDLE;
            cnn_start      <= 1'b0;
            detect_valid_ui <= 1'b0;
            detect_x_ui    <= 10'd0;
            detect_y_ui    <= 10'd0;
            detect_conf_ui <= 8'd0;
        end else begin
            cnn_start <= 1'b0;

            // Reset detection on new frame
            if (frame_start_ui_edge) begin
                inf_state <= INF_IDLE;
            end

            case (inf_state)
                INF_IDLE: begin
                    if (cnn_input_done && !cnn_busy) begin
                        cnn_start <= 1'b1;
                        inf_state <= INF_START;
                    end
                end

                INF_START: begin
                    // Wait one cycle for pipeline to register start
                    inf_state <= INF_RUNNING;
                end

                INF_RUNNING: begin
                    if (cnn_done) begin
                        detect_x_ui    <= cnn_detect_x;
                        detect_y_ui    <= cnn_detect_y;
                        detect_conf_ui <= cnn_detect_conf;
                        detect_valid_ui <= 1'b1;
                        inf_state       <= INF_DONE;
                    end
                end

                INF_DONE: begin
                    // Hold results until next frame resets us
                end
            endcase
        end
    end

    // SECTION 14: Detection Result CDC (ui_clk -> clk_25mhz)
    // Detection results change once per frame (~16ms) and are
    // stable for millions of cycles. Simple double-FF sync is safe
    // since all bits settle long before they're read.

    logic [9:0]  detect_x_px, detect_x_px2;
    logic [9:0]  detect_y_px, detect_y_px2;
    logic [7:0]  detect_conf_px, detect_conf_px2;
    logic        detect_valid_px, detect_valid_px2;

    always_ff @(posedge clk_25mhz) begin
        if (rst_25mhz) begin
            detect_x_px     <= 10'd0;
            detect_x_px2    <= 10'd0;
            detect_y_px     <= 10'd0;
            detect_y_px2    <= 10'd0;
            detect_conf_px  <= 8'd0;
            detect_conf_px2 <= 8'd0;
            detect_valid_px <= 1'b0;
            detect_valid_px2 <= 1'b0;
        end else begin
            // First stage
            detect_x_px     <= detect_x_ui;
            detect_y_px     <= detect_y_ui;
            detect_conf_px  <= detect_conf_ui;
            detect_valid_px <= detect_valid_ui;
            // Second stage (output)
            detect_x_px2     <= detect_x_px;
            detect_y_px2     <= detect_y_px;
            detect_conf_px2  <= detect_conf_px;
            detect_valid_px2 <= detect_valid_px;
        end
    end

    // SECTION 15: DDR3 Arbiter
    // Three clients: camera write, display read, CNN read (unused)

    // Display read signals
    logic        disp_rd_req;
    logic [27:0] disp_rd_addr;
    logic [127:0] disp_rd_data;
    logic        disp_rd_valid;

    // CNN read signals (tied off — CNN uses internal BRAM)
    logic        cnn_rd_req;
    logic [27:0] cnn_rd_addr;
    logic [127:0] cnn_rd_data;
    logic        cnn_rd_valid;

    assign cnn_rd_req  = 1'b0;
    assign cnn_rd_addr = 28'd0;

    ddr3_arbiter u_arbiter (
        .ui_clk         (ui_clk),
        .ui_rst         (ui_rst),
        .calib_complete (calib_complete),
        // Camera write
        .cam_wr_req     (cam_wr_req),
        .cam_wr_addr    (cam_wr_addr),
        .cam_wr_data    (cam_wr_data),
        .cam_wr_ack     (cam_wr_ack),
        // Display read
        .disp_rd_req    (disp_rd_req),
        .disp_rd_addr   (disp_rd_addr),
        .disp_rd_data   (disp_rd_data),
        .disp_rd_valid  (disp_rd_valid),
        // CNN read (unused)
        .cnn_rd_req     (cnn_rd_req),
        .cnn_rd_addr    (cnn_rd_addr),
        .cnn_rd_data    (cnn_rd_data),
        .cnn_rd_valid   (cnn_rd_valid),
        // MIG interface
        .app_addr       (mig_app_addr),
        .app_cmd        (mig_app_cmd),
        .app_en         (mig_app_en),
        .app_rdy        (mig_app_rdy),
        .app_wdf_data   (mig_app_wdf_data),
        .app_wdf_mask   (mig_app_wdf_mask),
        .app_wdf_wren   (mig_app_wdf_wren),
        .app_wdf_end    (mig_app_wdf_end),
        .app_wdf_rdy    (mig_app_wdf_rdy),
        .app_rd_data    (mig_app_rd_data),
        .pp_rd_data_valid (mig_app_rd_data_valid),  // Note: arbiter port name
        .app_rd_data_end  (mig_app_rd_data_end)
    );

    // SECTION 16: HDMI Timing Generator
    logic        hdmi_hsync, hdmi_vsync;
    logic        hdmi_active;
    logic [9:0]  hdmi_pixel_x, hdmi_pixel_y;
    logic        hdmi_hblank, hdmi_vblank;
    logic        hdmi_frame_start;

    hdmi_timing u_hdmi_timing (
        .pixel_clk   (clk_25mhz),
        .rst         (rst_25mhz),
        .hsync       (hdmi_hsync),
        .vsync       (hdmi_vsync),
        .active      (hdmi_active),
        .pixel_x     (hdmi_pixel_x),
        .pixel_y     (hdmi_pixel_y),
        .hblank      (hdmi_hblank),
        .vblank      (hdmi_vblank),
        .frame_start (hdmi_frame_start)
    );

    // SECTION 17: DDR3 -> Display Read Path
    // Show test pattern until DDR3 calibration completes,
    // then switch to live camera feed.

    logic [7:0] disp_r, disp_g, disp_b;
    logic       use_test_pattern;

    assign use_test_pattern = ~calib_complete;

    ddr3_to_display u_ddr3_to_display (
        .pixel_clk        (clk_25mhz),
        .rst              (rst_25mhz),
        .active           (hdmi_active),
        .pixel_x          (hdmi_pixel_x),
        .pixel_y          (hdmi_pixel_y),
        .pixel_r          (disp_r),
        .pixel_g          (disp_g),
        .pixel_b          (disp_b),
        .use_test_pattern (use_test_pattern),
        .ui_clk           (ui_clk),
        .ui_rst           (ui_rst),
        .disp_rd_req      (disp_rd_req),
        .disp_rd_addr     (disp_rd_addr),
        .disp_rd_data     (disp_rd_data),
        .disp_rd_valid    (disp_rd_valid),
        .fb_base_addr     (disp_fb_base)
    );

    // SECTION 18: Bounding Box Overlay
    logic [7:0] overlay_r, overlay_g, overlay_b;

    bbox_overlay u_bbox (
        .pixel_clk    (clk_25mhz),
        .rst          (rst_25mhz),
        .pixel_x      (hdmi_pixel_x),
        .pixel_y      (hdmi_pixel_y),
        .active       (hdmi_active),
        .pixel_r_in   (disp_r),
        .pixel_g_in   (disp_g),
        .pixel_b_in   (disp_b),
        .pixel_r_out  (overlay_r),
        .pixel_g_out  (overlay_g),
        .pixel_b_out  (overlay_b),
        .detect_x     (detect_x_px2),
        .detect_y     (detect_y_px2),
        .detect_conf  (detect_conf_px2),
        .detect_valid (detect_valid_px2)
    );

    // SECTION 19: HDMI Output
    hdmi_top u_hdmi (
        .pixel_clk  (clk_25mhz),
        .serial_clk (clk_125mhz),
        .rst        (rst_25mhz),
        .pixel_r    (overlay_r),
        .pixel_g    (overlay_g),
        .pixel_b    (overlay_b),
        .active     (hdmi_active),
        .hsync      (hdmi_hsync),
        .vsync      (hdmi_vsync),
        .hdmi_clk_p (hdmi_clk_p),
        .hdmi_clk_n (hdmi_clk_n),
        .hdmi_d0_p  (hdmi_d0_p),
        .hdmi_d0_n  (hdmi_d0_n),
        .hdmi_d1_p  (hdmi_d1_p),
        .hdmi_d1_n  (hdmi_d1_n),
        .hdmi_d2_p  (hdmi_d2_p),
        .hdmi_d2_n  (hdmi_d2_n)
    );

    // SECTION 20: Debug LEDs
    // LED[0]: Clock PLL locked
    // LED[1]: DDR3 calibration complete
    // LED[2]: CNN busy (blinks during inference)
    // LED[3]: Detection valid (stays on when object detected)

    always_ff @(posedge ui_clk) begin
        if (ui_rst) begin
            debug_led <= 4'b0000;
        end else begin
            debug_led[0] <= clk_locked;
            debug_led[1] <= calib_complete;
            debug_led[2] <= cnn_busy;
            debug_led[3] <= detect_valid_ui;
        end
    end

endmodule