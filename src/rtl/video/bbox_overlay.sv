// bbox_overlay.sv
// Draws a bounding box rectangle on the video output.
// Sits in the pixel path between ddr3_to_display and hdmi_top.

module bbox_overlay (
    input pixel_clk,
    input rst,

    // Video timing inputs
    input [9:0] pixel_x,
    input [9:0] pixel_y,
    input       active,

    // Input pixels (from ddr3_to_display)
    input [7:0] pixel_r_in,
    input [7:0] pixel_g_in,
    input [7:0] pixel_b_in,

    // Output pixels (to hdmi_top)
    output logic [7:0] pixel_r_out,
    output logic [7:0] pixel_g_out,
    output logic [7:0] pixel_b_out,

    // Detection results (from CNN)
    input [9:0] detect_x,      // center X in 640x480 space
    input [9:0] detect_y,      // center Y in 640x480 space
    input [7:0] detect_conf,   // confidence 0-255
    input       detect_valid   // high when a valid detection exists
);

    // CONFIGURATION: Box and Border settings
    
    // Box half-dimensions (80x60 scaled grid cell)
    localparam [9:0] HALF_W = 10'd40;
    localparam [9:0] HALF_H = 10'd30;

    localparam [9:0] BORDER = 10'd2;      // Border thickness
    localparam [7:0] CONF_THRESH = 8'd32; // Drawing threshold

    // Box color: bright green
    localparam [7:0] BOX_R = 8'h00;
    localparam [7:0] BOX_G = 8'hFF;
    localparam [7:0] BOX_B = 8'h00;

    // BOX CORNER COMPUTATION: Clamped to screen edges
    logic [9:0] box_left, box_right, box_top, box_bottom;

    always_comb begin
        // Left edge
        if (detect_x >= HALF_W)
            box_left = detect_x - HALF_W;
        else
            box_left = 10'd0;

        // Right edge
        if ((detect_x + HALF_W) <= 10'd639)
            box_right = detect_x + HALF_W;
        else
            box_right = 10'd639;

        // Top edge
        if (detect_y >= HALF_H)
            box_top = detect_y - HALF_H;
        else
            box_top = 10'd0;

        // Bottom edge
        if ((detect_y + HALF_H) <= 10'd479)
            box_bottom = detect_y + HALF_H;
        else
            box_bottom = 10'd479;
    end

    // BORDER HIT DETECTION: Logic to determine if current pixel is on the box edge
    logic in_h_range;   // pixel_x within [box_left, box_right]
    logic in_v_range;   // pixel_y within [box_top, box_bottom]

    logic on_top_edge;
    logic on_bottom_edge;
    logic on_left_edge;
    logic on_right_edge;

    logic on_border;
    logic draw_enable;

    always_comb begin
        in_h_range = (pixel_x >= box_left) && (pixel_x <= box_right);
        in_v_range = (pixel_y >= box_top)  && (pixel_y <= box_bottom);

        on_top_edge    = in_h_range && (pixel_y >= box_top) && (pixel_y < (box_top + BORDER));
        on_bottom_edge = in_h_range && (pixel_y <= box_bottom) && (pixel_y > (box_bottom - BORDER));
        on_left_edge   = in_v_range && (pixel_x >= box_left) && (pixel_x < (box_left + BORDER));
        on_right_edge  = in_v_range && (pixel_x <= box_right) && (pixel_x > (box_right - BORDER));

        on_border = on_top_edge | on_bottom_edge | on_left_edge | on_right_edge;

        // Final draw conditions
        draw_enable = detect_valid && (detect_conf >= CONF_THRESH) && on_border && active;
    end

    // PIXEL OUTPUT: Registered for clean timing
    always_ff @(posedge pixel_clk) begin
        if (rst) begin
            pixel_r_out <= 8'd0;
            pixel_g_out <= 8'd0;
            pixel_b_out <= 8'd0;
        end else begin
            if (draw_enable) begin
                // Draw box border
                pixel_r_out <= BOX_R;
                pixel_g_out <= BOX_G;
                pixel_b_out <= BOX_B;
            end else begin
                // Pass through original pixel
                pixel_r_out <= pixel_r_in;
                pixel_g_out <= pixel_g_in;
                pixel_b_out <= pixel_b_in;
            end
        end
    end

endmodule