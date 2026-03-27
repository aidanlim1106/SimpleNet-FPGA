
// Capture pixels from OV7670's parallel interface
// The OV7670 streams pixels synchronized to PCLK:
//   - VSYNC pulse -> new frame starting
//   - HREF high -> active pixel data in this row
//   - D[7:0] -> one byte per PCLK rising edge
//   - Two bytes per pixel
//   1. Detects new frames via VSYNC
//   2. Captures bytes during HREF
//   3. Pairs bytes into 16-bit RGB565 pixels
//   4. Outputs pixel + address + valid flag

module ov7670_capture (
    input pclk,           
    input rst,           
    input vsync,        
    input href,           
    input [7:0] d,            
    output logic [15:0] pixel_data,  
    output logic pixel_valid, 
    output logic [18:0] pixel_addr,  
    output logic frame_start, 
    output logic frame_done   
);

    logic byte_toggle;     // 0 = first, 1 = second
    logic [7:0] byte_latch;      // holds first byte while waiting for second
    logic [9:0] col_count;       // pixel clm
    logic [8:0] row_count;       // pixel row
    logic vsync_prev;     
    logic frame_active;    

    always_ff @(posedge pclk) begin
        if (rst) begin
            vsync_prev   <= 1'b0;
            frame_active <= 1'b0;
            frame_start  <= 1'b0;
            frame_done   <= 1'b0;
        end else begin
            vsync_prev  <= vsync;
            frame_start <= 1'b0;   
            frame_done  <= 1'b0;
            // VSYNC rising edge -> frame is starting
            if (vsync && !vsync_prev) begin
                frame_done   <= frame_active; 
                frame_active <= 1'b1;
            end
            if (!vsync && vsync_prev) begin
                frame_start <= 1'b1; // active pixel area starts
            end
        end
    end

    // Pixel capture
    always_ff @(posedge pclk) begin
        if (rst) begin
            byte_toggle <= 1'b0;
            byte_latch  <= 8'd0;
            col_count   <= 10'd0;
            row_count   <= 9'd0;
            pixel_data  <= 16'd0;
            pixel_valid <= 1'b0;
            pixel_addr  <= 19'd0;
        end else begin
            pixel_valid <= 1'b0;
            // Reset counters on new frame
            if (vsync && !vsync_prev) begin
                col_count   <= 10'd0;
                row_count   <= 9'd0;
                byte_toggle <= 1'b0;
            end
            if (href && !vsync) begin
                if (!byte_toggle) begin
                    byte_latch  <= d;
                    byte_toggle <= 1'b1;

                end else begin
                    pixel_data  <= {byte_latch, d};
                    pixel_addr  <= {9'b0, row_count} * 19'd640
                                 + {9'b0, col_count};
                    pixel_valid <= 1'b1;
                    byte_toggle <= 1'b0;
                    if (col_count == 10'd639) begin
                        col_count <= 10'd0;
                        row_count <= row_count + 9'd1;
                    end else begin
                        col_count <= col_count + 10'd1;
                    end
                end

            end else begin
                byte_toggle <= 1'b0;
            end
        end
    end

endmodule