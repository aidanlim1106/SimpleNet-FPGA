// adapts camera pixel output to DDR3 write interface.
//   1. Collect 8 pixels (8 × 16 = 128 bits) in camera domain
//   2. Push the 128-bit word through an async FIFO
//   3. Pop from FIFO in DDR3 domain and issue write commands
//
// Data packing -> each pixel goes into 16 bits


module cam_to_ddr3 (
    // camera
    input pclk,
    input pclk_rst,
    input [15:0] pixel_data,      
    input pixel_valid,     
    input frame_start,  
    // ddr
    input ui_clk,
    input ui_rst,
    output logic cam_wr_req,      
    output logic [27:0] cam_wr_addr,     
    output logic [127:0] cam_wr_data,   
    input cam_wr_ack,    
    input [27:0] fb_base_addr // base address
);
    // packing pixel from camera
    logic [127:0] pack_register;
    logic [2:0] pack_count;      
    logic pack_ready;      
    logic [27:0] pixel_byte_addr;  

    always_ff @(posedge pclk) begin
        if (pclk_rst) begin
            pack_register  <= 128'd0;
            pack_count     <= 3'd0;
            pack_ready     <= 1'b0;
            pixel_byte_addr <= 28'd0;
        end else begin
            pack_ready <= 1'b0;    
            if (frame_start) begin
                pixel_byte_addr <= 28'd0;
                pack_count      <= 3'd0;
            end
            if (pixel_valid) begin
                case (pack_count)
                    3'd0: pack_register[15:0]    <= pixel_data;
                    3'd1: pack_register[31:16]   <= pixel_data;
                    3'd2: pack_register[47:32]   <= pixel_data;
                    3'd3: pack_register[63:48]   <= pixel_data;
                    3'd4: pack_register[79:64]   <= pixel_data;
                    3'd5: pack_register[95:80]   <= pixel_data;
                    3'd6: pack_register[111:96]  <= pixel_data;
                    3'd7: pack_register[127:112] <= pixel_data;
                endcase
                if (pack_count == 3'd7) begin
                    pack_ready      <= 1'b1;      
                    pack_count      <= 3'd0;
                    pixel_byte_addr <= pixel_byte_addr + 28'd16;
                end else begin
                    pack_count <= pack_count + 3'd1;
                end
            end
        end
    end
    // Camera domain -> DDR3 domain
    logic fifo_wr_en;
    logic [155:0] fifo_wr_data;
    logic fifo_full;
    logic fifo_rd_en;
    logic [155:0] fifo_rd_data;
    logic fifo_empty;

    assign fifo_wr_en = pack_ready && !fifo_full;
    assign fifo_wr_data = {pixel_byte_addr, pack_register};

    async_fifo #(
        .DATA_WIDTH (156),
        .ADDR_WIDTH (4)     
    ) u_cam_fifo (
        .wr_clk   (pclk),
        .wr_rst   (pclk_rst),
        .wr_en    (fifo_wr_en),
        .wr_data  (fifo_wr_data),
        .wr_full  (fifo_full),

        .rd_clk   (ui_clk),
        .rd_rst   (ui_rst),
        .rd_en    (fifo_rd_en),
        .rd_data  (fifo_rd_data),
        .rd_empty (fifo_empty)
    );
    // write request
    typedef enum logic [1:0] {
        WR_IDLE,
        WR_REQUEST,
        WR_WAIT_ACK
    } wr_state_t;

    wr_state_t wr_state;

    always_ff @(posedge ui_clk) begin
        if (ui_rst) begin
            wr_state   <= WR_IDLE;
            cam_wr_req <= 1'b0;
            fifo_rd_en <= 1'b0;
        end else begin
            fifo_rd_en <= 1'b0; 
            cam_wr_req <= 1'b0;

            case (wr_state)

                WR_IDLE: begin
                    if (!fifo_empty) begin
                        fifo_rd_en <= 1'b1;
                        wr_state   <= WR_REQUEST;
                    end
                end
                WR_REQUEST: begin
                    cam_wr_addr <= fb_base_addr + fifo_rd_data[155:128];
                    cam_wr_data <= fifo_rd_data[127:0];
                    cam_wr_req  <= 1'b1;
                    wr_state    <= WR_WAIT_ACK;
                end
                WR_WAIT_ACK: begin
                    cam_wr_req <= 1'b1;   
                    if (cam_wr_ack) begin
                        cam_wr_req <= 1'b0;
                        wr_state   <= WR_IDLE;
                    end
                end
            endcase
        end
    end

endmodule