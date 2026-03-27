// downsample 640×480 RGB565 frame to 128×128 grayscale image for CNN processing.
// Operation:
//   Watches the camera pixel stream.
//   For each of the 128×128 output pixels, it picks the
//   nearest source pixel and converts it to grayscale.
//   Writes the result to the CNN region in DDR3.
// Pixel selection (nearest-neighbor):
//   out_x = 0..127
//   out_y = 0..127
//   src_x = out_x × 5     
//   src_y = (out_y × 15) >> 2  

module downsample_128 (
    input pclk,        
    input rst,
    input [15:0] pixel_data,   
    input pixel_valid,
    input [9:0] pixel_col,   
    input [8:0] pixel_row,      
    input frame_start,
    output logic [7:0] ds_pixel_data, 
    output logic ds_pixel_valid,  
    output logic [13:0] ds_pixel_addr  
);

    logic [6:0] out_x;     
    logic [6:0] out_y;   
    logic [9:0] src_x; // out_x × 5
    logic [8:0] src_y; // (out_y × 15) >> 2

    assign src_x = {3'b0, out_x} + {1'b0, out_x, 2'b0};  // out_x × 5

    logic [12:0] src_y_full;
    assign src_y_full = ({2'b0, out_y, 4'b0} - {6'b0, out_y});  // out_y × 15
    assign src_y      = src_y_full[10:2];                         // >> 2

    logic [7:0] r8, g8, b8;

    assign r8 = {pixel_data[15:11], pixel_data[15:13]};   
    assign g8 = {pixel_data[10:5],  pixel_data[10:9]};
    assign b8 = {pixel_data[4:0],   pixel_data[4:2]}; 

    // gray = (77×R + 150×G + 29×B) >> 8
    logic [15:0] gray_sum;
    logic [7:0]  gray_pixel;

    always_comb begin
        gray_sum   = (16'(r8) * 16'd77) +
                     (16'(g8) * 16'd150) +
                     (16'(b8) * 16'd29);
        gray_pixel = gray_sum[15:8];
    end

    logic       row_match;
    logic       col_match;
    logic       pixel_match;

    assign row_match   = (pixel_row == src_y);
    assign col_match   = (pixel_col == src_x);
    assign pixel_match = row_match && col_match && pixel_valid;

    always_ff @(posedge pclk) begin
        if (rst) begin
            out_x          <= 7'd0;
            out_y          <= 7'd0;
            ds_pixel_valid <= 1'b0;
            ds_pixel_data  <= 8'd0;
            ds_pixel_addr  <= 14'd0;
        end else begin
            ds_pixel_valid <= 1'b0;  
            if (frame_start) begin
                out_x <= 7'd0;
                out_y <= 7'd0;
            end
            // when incoming pixel matches our target position
            if (pixel_match) begin
                // output grayscale pixel
                ds_pixel_data  <= gray_pixel;
                ds_pixel_addr  <= {out_y, out_x};
                ds_pixel_valid <= 1'b1;
                // go to next output pixel
                if (out_x == 7'd127) begin
                    out_x <= 7'd0;
                    if (out_y < 7'd127) begin
                        out_y <= out_y + 7'd1;
                    end
                end else begin
                    out_x <= out_x + 7'd1;
                end
            end
        end
    end

endmodule