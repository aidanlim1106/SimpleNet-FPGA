`timescale 1ns / 1ps

module tb_hdmi_timing;
    logic pixel_clk = 0;
    always #20 pixel_clk = ~pixel_clk;
    logic rst;
    logic hsync, vsync;
    logic active;
    logic [9:0] pixel_x, pixel_y;
    logic hblank, vblank;
    logic frame_start;
    hdmi_timing u_dut (
        .pixel_clk   (pixel_clk),
        .rst         (rst),
        .hsync       (hsync),
        .vsync       (vsync),
        .active      (active),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y),
        .hblank      (hblank),
        .vblank      (vblank),
        .frame_start (frame_start)
    );

    int clocks_per_line;
    int lines_per_frame;
    int active_pixels_per_line;
    int active_lines;
    int hsync_count;
    int frame_count;
    logic hsync_prev;
    int   h_counter;

    always_ff @(posedge pixel_clk) begin
        hsync_prev <= hsync;
        h_counter <= h_counter + 1;
        if (hsync && !hsync_prev) begin
            clocks_per_line <= h_counter;
            h_counter       <= 0;
            hsync_count     <= hsync_count + 1;
        end
    end

    int active_h_count;
    logic active_prev;

    always_ff @(posedge pixel_clk) begin
        active_prev <= active;
        if (active) active_h_count <= active_h_count + 1;
        if (!active && active_prev) begin
            active_pixels_per_line <= active_h_count;
            active_h_count         <= 0;
        end
    end

    logic vsync_prev;
    always_ff @(posedge pixel_clk) begin
        vsync_prev <= vsync;
        if (vsync && !vsync_prev) begin
            frame_count <= frame_count + 1;
        end
    end

    initial begin
        rst = 1'b1;
        h_counter       = 0;
        clocks_per_line = 0;
        active_h_count  = 0;
        active_pixels_per_line = 0;
        hsync_count     = 0;
        frame_count     = 0;

        #200;
        rst = 1'b0;

        $display("[%0t] Waiting for 2 complete frames...", $time);
        wait (frame_count >= 2);

        $display("\n=============================");
        $display("  TIMING MEASUREMENT RESULTS");
        $display("=============================");
        $display("  Clocks per line:        %0d (expected 800)",
                 clocks_per_line);
        $display("  Active pixels per line: %0d (expected 640)",
                 active_pixels_per_line);
        $display("  HSYNC edges counted:    %0d", hsync_count);
        $display("  Frames counted:         %0d", frame_count);

        if (clocks_per_line == 800 && active_pixels_per_line == 640)
            $display("\n  ✅ ALL TIMING CHECKS PASSED!\n");
        else
            $display("\n  ❌ TIMING MISMATCH — CHECK PARAMETERS!\n");

        $finish;
    end
    initial begin
        #40_000_000;  
        $display("ERROR: Simulation timed out!");
        $finish;
    end

endmodule