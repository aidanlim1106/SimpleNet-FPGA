// Test HDMI output with color bars.

module top_hdmi_test (
    input  logic sys_clk,
    output logic hdmi_clk_p,
    output logic hdmi_clk_n,
    output logic hdmi_d0_p,
    output logic hdmi_d0_n,
    output logic hdmi_d1_p,
    output logic hdmi_d1_n,
    output logic hdmi_d2_p,
    output logic hdmi_d2_n,
    output logic [3:0] debug_led
);

    logic clk_24mhz, clk_25mhz, clk_125mhz;
    logic rst_24mhz, rst_25mhz, rst_125mhz;
    logic locked;

    clk_generator u_clk (
        .sys_clk     (sys_clk),
        .clk_24mhz   (clk_24mhz),
        .clk_25mhz   (clk_25mhz),
        .clk_125mhz  (clk_125mhz),
        .rst_24mhz   (rst_24mhz),
        .rst_25mhz   (rst_25mhz),
        .rst_125mhz  (rst_125mhz),
        .locked       (locked)
    );

    // Video Timing
    logic       hsync, vsync, active;
    logic [9:0] pixel_x, pixel_y;
    logic       hblank, vblank, frame_start;

    hdmi_timing u_timing (
        .pixel_clk   (clk_25mhz),
        .rst         (rst_25mhz),
        .hsync       (hsync),
        .vsync       (vsync),
        .active      (active),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y),
        .hblank      (hblank),
        .vblank      (vblank),
        .frame_start (frame_start)
    );

    logic [7:0] pixel_r, pixel_g, pixel_b;

    ddr3_to_display u_display (
        .pixel_clk        (clk_25mhz),
        .rst              (rst_25mhz),
        .active           (active),
        .pixel_x          (pixel_x),
        .pixel_y          (pixel_y),
        .pixel_r          (pixel_r),
        .pixel_g          (pixel_g),
        .pixel_b          (pixel_b),
        .use_test_pattern (1'b1),       
        .ui_clk           (clk_25mhz),  
        .ui_rst           (rst_25mhz),
        .disp_rd_req      (),             
        .disp_rd_addr     (),           
        .disp_rd_data     (128'd0),       
        .disp_rd_valid    (1'b0),          
        .fb_base_addr     (28'd0)         
    );

    hdmi_top u_hdmi (
        .pixel_clk  (clk_25mhz),
        .serial_clk (clk_125mhz),
        .rst        (rst_25mhz),
        .pixel_r    (pixel_r),
        .pixel_g    (pixel_g),
        .pixel_b    (pixel_b),
        .active     (active),
        .hsync      (hsync),
        .vsync      (vsync),
        .hdmi_clk_p (hdmi_clk_p),
        .hdmi_clk_n (hdmi_clk_n),
        .hdmi_d0_p  (hdmi_d0_p),
        .hdmi_d0_n  (hdmi_d0_n),
        .hdmi_d1_p  (hdmi_d1_p),
        .hdmi_d1_n  (hdmi_d1_n),
        .hdmi_d2_p  (hdmi_d2_p),
        .hdmi_d2_n  (hdmi_d2_n)
    );

    // LED[0]: Clocks are locked and stable
    // LED[1]: VSYNC is toggling (video is running)
    // LED[2]: HSYNC is toggling
    // LED[3]: Heartbeat (slow blink = system alive)
    assign debug_led[0] = locked;

    // If VSYNC toggles at least once per ~0.5 seconds,
    // LED stays on. If it stops, LED goes dark.
    logic [24:0] vsync_watchdog;
    logic        vsync_prev;
    logic        vsync_seen;

    always_ff @(posedge clk_25mhz) begin
        if (rst_25mhz) begin
            vsync_watchdog <= 25'd0;
            vsync_prev     <= 1'b0;
            vsync_seen     <= 1'b0;
        end else begin
            vsync_prev <= vsync;
            if (vsync && !vsync_prev) begin
                vsync_seen <= 1'b1;
            end
            if (vsync_watchdog == 25'd16_777_215) begin
                vsync_watchdog <= 25'd0;
                debug_led[1]   <= vsync_seen; 
                vsync_seen     <= 1'b0;          
            end else begin
                vsync_watchdog <= vsync_watchdog + 25'd1;
            end
        end
    end

    logic [19:0] hsync_watchdog;
    logic        hsync_prev;
    logic        hsync_seen;

    always_ff @(posedge clk_25mhz) begin
        if (rst_25mhz) begin
            hsync_watchdog <= 20'd0;
            hsync_prev     <= 1'b0;
            hsync_seen     <= 1'b0;
        end else begin
            hsync_prev <= hsync;
            if (hsync && !hsync_prev) begin
                hsync_seen <= 1'b1;
            end
            if (hsync_watchdog == 20'd999_999) begin
                hsync_watchdog <= 20'd0;
                debug_led[2]   <= hsync_seen;
                hsync_seen     <= 1'b0;
            end else begin
                hsync_watchdog <= hsync_watchdog + 20'd1;
            end
        end
    end

    logic [25:0] heartbeat_count;

    always_ff @(posedge clk_25mhz) begin
        if (rst_25mhz) begin
            heartbeat_count <= 26'd0;
        end else begin
            heartbeat_count <= heartbeat_count + 26'd1;
        end
    end

    assign debug_led[3] = heartbeat_count[25]; // Toggles every 1.3s

endmodule