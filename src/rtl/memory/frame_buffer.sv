// manages DDR3 address generation and double-buffer
// Double buffering explained:
//   While camera writes to Frame Buffer 0,
//   the display reads from Frame Buffer 1.

module frame_buffer_ctrl (
    input clk,           
    input rst,
    input vsync_edge, // swap trigger
    input cam_pixel_valid,
    output logic [27:0] cam_wr_addr, 
    output logic cam_frame_sel,   
    input disp_req,      
    output logic [27:0] disp_rd_addr,    
    output logic disp_frame_sel,  
    input cnn_req,        
    output logic [27:0] cnn_rd_addr  
);

    localparam logic [27:0] FB0_BASE  = 28'h000_0000;
    localparam logic [27:0] FB1_BASE  = 28'h010_0000;
    localparam logic [27:0] CNN_BASE  = 28'h020_0000;

    // Frame size in bytes: 614,400 -> /16 == 38,400
    localparam logic [27:0] FRAME_SIZE = 28'h009_6000;
    // CNN image size = 16,384
    localparam logic [27:0] CNN_SIZE   = 28'h000_4000;

    logic write_sel;

    always_ff @(posedge clk) begin
        if (rst) begin
            write_sel <= 1'b0;
        end else if (vsync_edge) begin
            write_sel <= ~write_sel;  
        end
    end

    assign cam_frame_sel  = write_sel;
    assign disp_frame_sel = ~write_sel; 

    logic [27:0] cam_offset;

    always_ff @(posedge clk) begin
        if (rst) begin
            cam_offset <= 28'd0;
        end else if (vsync_edge) begin
            cam_offset <= 28'd0;         
        end else if (cam_pixel_valid) begin
            if (cam_offset < FRAME_SIZE - 16) begin
                cam_offset <= cam_offset + 28'd16; 
            end
        end
    end

    assign cam_wr_addr = (write_sel ? FB1_BASE : FB0_BASE) + cam_offset;

    logic [27:0] disp_offset;

    always_ff @(posedge clk) begin
        if (rst) begin
            disp_offset <= 28'd0;
        end else if (vsync_edge) begin
            disp_offset <= 28'd0;
        end else if (disp_req) begin
            if (disp_offset < FRAME_SIZE - 16) begin
                disp_offset <= disp_offset + 28'd16;
            end
        end
    end

    assign disp_rd_addr = (write_sel ? FB0_BASE : FB1_BASE) + disp_offset;

    logic [27:0] cnn_offset;

    always_ff @(posedge clk) begin
        if (rst) begin
            cnn_offset <= 28'd0;
        end else if (vsync_edge) begin
            cnn_offset <= 28'd0;
        end else if (cnn_req) begin
            if (cnn_offset < CNN_SIZE - 16) begin
                cnn_offset <= cnn_offset + 28'd16;
            end
        end
    end

    assign cnn_rd_addr = CNN_BASE + cnn_offset;

endmodule