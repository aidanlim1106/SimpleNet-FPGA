
// feeds pixel data to the HDMI output.
// Two modes:
//   MODE 0: Test pattern (color bars) — for initial HDMI debug
//   MODE 1: DDR3 read — real camera data from frame buffer

module ddr3_to_display (
    input pixel_clk, // 25 MHz
    input rst,
    // Video timing inputs
    input active,
    input [9:0] pixel_x,
    input [9:0] pixel_y,
    // Pixel outputs (to HDMI encoder)
    output logic [7:0]  pixel_r,
    output logic [7:0]  pixel_g,
    output logic [7:0]  pixel_b,
    input use_test_pattern,  // 1=test bars, 0=DDR3
    input ui_clk,
    input ui_rst,
    output logic disp_rd_req,
    output logic [27:0] disp_rd_addr,
    input [127:0] disp_rd_data,
    input disp_rd_valid,

    input [27:0] fb_base_addr   
);

    // TEST PATTERN: Color Bars
    logic [7:0] test_r, test_g, test_b;

    always_comb begin
        case (pixel_x[9:7])   
            3'd0: begin test_r = 8'hFF; test_g = 8'hFF; test_b = 8'hFF; end  // White
            3'd1: begin test_r = 8'hFF; test_g = 8'hFF; test_b = 8'h00; end  // Yellow
            3'd2: begin test_r = 8'h00; test_g = 8'hFF; test_b = 8'hFF; end  // Cyan
            3'd3: begin test_r = 8'h00; test_g = 8'hFF; test_b = 8'h00; end  // Green
            3'd4: begin test_r = 8'hFF; test_g = 8'h00; test_b = 8'hFF; end  // Magenta
            3'd5: begin test_r = 8'hFF; test_g = 8'h00; test_b = 8'h00; end  // Red
            3'd6: begin test_r = 8'h00; test_g = 8'h00; test_b = 8'hFF; end  // Blue
            3'd7: begin test_r = 8'h00; test_g = 8'h00; test_b = 8'h00; end  // Black
        endcase
    end

    // Reads 128-bit words from DDR3, unpacks into individual RGB565 pixels, converts to RGB888.

    // Pixel FIFO
    logic [23:0] pixel_fifo [0:15];  
    logic [3:0]  fifo_wr_ptr;
    logic [3:0]  fifo_rd_ptr;
    logic [4:0]  fifo_count;     
    logic [7:0]  ddr3_r, ddr3_g, ddr3_b;
    logic [23:0] current_pixel;
    assign current_pixel = pixel_fifo[fifo_rd_ptr];
    assign ddr3_r = current_pixel[23:16];
    assign ddr3_g = current_pixel[15:8];
    assign ddr3_b = current_pixel[7:0];

    typedef enum logic [1:0] {
        RD_IDLE,
        RD_REQUEST,
        RD_UNPACK
    } rd_state_t;

    rd_state_t rd_state;
    logic [27:0] read_offset;
    logic [2:0]  unpack_index;

    always_ff @(posedge ui_clk) begin
        if (ui_rst) begin
            rd_state    <= RD_IDLE;
            disp_rd_req <= 1'b0;
            read_offset <= 28'd0;
        end else begin
            disp_rd_req <= 1'b0;
            case (rd_state)
                RD_IDLE: begin
                    if (!use_test_pattern && fifo_count < 5'd8) begin
                        disp_rd_req  <= 1'b1;
                        disp_rd_addr <= fb_base_addr + read_offset;
                        rd_state     <= RD_REQUEST;
                    end
                end
                RD_REQUEST: begin
                    disp_rd_req <= 1'b1;
                    if (disp_rd_valid) begin
                        disp_rd_req <= 1'b0;
                        unpack_index <= 3'd0;
                        rd_state     <= RD_UNPACK;
                    end
                end
                RD_UNPACK: begin
                    read_offset <= read_offset + 28'd16;
                    rd_state    <= RD_IDLE;
                end
            endcase
        end
    end

    always_ff @(posedge pixel_clk) begin
        if (rst) begin
            fifo_rd_ptr <= 4'd0;
        end else if (active && !use_test_pattern) begin
            fifo_rd_ptr <= fifo_rd_ptr + 4'd1;
        end
    end

    always_ff @(posedge pixel_clk) begin
        if (rst) begin
            pixel_r <= 8'd0;
            pixel_g <= 8'd0;
            pixel_b <= 8'd0;
        end else begin
            if (!active) begin
                pixel_r <= 8'd0;
                pixel_g <= 8'd0;
                pixel_b <= 8'd0;
            end else if (use_test_pattern) begin
                pixel_r <= test_r;
                pixel_g <= test_g;
                pixel_b <= test_b;
            end else begin
                pixel_r <= ddr3_r;
                pixel_g <= ddr3_g;
                pixel_b <= ddr3_b;
            end
        end
    end

endmodule