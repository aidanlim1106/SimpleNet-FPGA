//  controls DDR3 from three clients:
//      1. Camera (write)  — highest 
//      2. Display (read)  — medium 
//      3. CNN (read)      — lowest 

module ddr3_arbiter (
    input ui_clk, // ~83 MHz from MIG
    input ui_rst,         
    input calib_complete, // ddr ready

    // Camera Write
    input cam_wr_req,      
    input [27:0] cam_wr_addr,      
    input [127:0] cam_wr_data,  
    output logic cam_wr_ack,    

    // Display Read
    input disp_rd_req,    
    input [27:0] disp_rd_addr,    
    output logic [127:0] disp_rd_data,   
    output logic disp_rd_valid,   

    // CNN Read
    input cnn_rd_req,     
    input [27:0] cnn_rd_addr,    
    output logic [127:0] cnn_rd_data,    
    output logic cnn_rd_valid,   

    // MIG App Interface
    output logic [27:0] app_addr,
    output logic [2:0] app_cmd, // 000=Write, 001=Read
    output logic app_en,          
    input app_rdy, 

    output logic [127:0] app_wdf_data,  
    output logic [15:0]  app_wdf_mask,     // (0=write)
    output logic app_wdf_wren, 
    output logic app_wdf_end,   
    input app_wdf_rdy,  

    input [127:0] app_rd_data,     
    input pp_rd_data_valid, 
    input app_rd_data_end  
);

    localparam logic [2:0] CMD_WRITE = 3'b000;
    localparam logic [2:0] CMD_READ  = 3'b001;
    typedef enum logic [3:0] {
        S_IDLE,         // Waiting for requests
        S_CAM_CMD,      // Issue camera write command
        S_CAM_DATA,     // Send camera write data
        S_DISP_CMD,     // Issue display read command
        S_DISP_WAIT,    // Wait for display read data
        S_CNN_CMD,      // Issue CNN read command
        S_CNN_WAIT      // Wait for CNN read data
    } state_t;

    state_t state;

    typedef enum logic [1:0] {
        RD_NONE,
        RD_DISP,
        RD_CNN
    } rd_owner_t;

    rd_owner_t rd_owner;

    always_ff @(posedge ui_clk) begin
        if (ui_rst || !calib_complete) begin
            state       <= S_IDLE;
            rd_owner    <= RD_NONE;
            app_en      <= 1'b0;
            app_wdf_wren <= 1'b0;
            app_wdf_end  <= 1'b0;
            cam_wr_ack  <= 1'b0;
            disp_rd_valid <= 1'b0;
            cnn_rd_valid  <= 1'b0;
        end else begin
            app_en       <= 1'b0;
            app_wdf_wren <= 1'b0;
            app_wdf_end  <= 1'b0;
            cam_wr_ack   <= 1'b0;
            disp_rd_valid <= 1'b0;
            cnn_rd_valid  <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (cam_wr_req) begin
                        state <= S_CAM_CMD;
                    end else if (disp_rd_req) begin
                        state <= S_DISP_CMD;
                    end else if (cnn_rd_req) begin
                        state <= S_CNN_CMD;
                    end
                end
                S_CAM_CMD: begin
                    if (app_rdy) begin
                        app_addr <= cam_wr_addr;
                        app_cmd  <= CMD_WRITE;
                        app_en   <= 1'b1;
                        state    <= S_CAM_DATA;
                    end
                end
                S_CAM_DATA: begin
                    if (app_wdf_rdy) begin
                        app_wdf_data <= cam_wr_data;
                        app_wdf_mask <= 16'h0000;   
                        app_wdf_wren <= 1'b1;
                        app_wdf_end  <= 1'b1;      
                        cam_wr_ack   <= 1'b1;      
                        state        <= S_IDLE;
                    end
                end
                S_DISP_CMD: begin
                    if (app_rdy) begin
                        app_addr <= disp_rd_addr;
                        app_cmd  <= CMD_READ;
                        app_en   <= 1'b1;
                        rd_owner <= RD_DISP;
                        state    <= S_DISP_WAIT;
                    end
                end

                S_DISP_WAIT: begin
                    if (app_rd_data_valid) begin
                        disp_rd_data  <= app_rd_data;
                        disp_rd_valid <= 1'b1;
                        state         <= S_IDLE;
                    end
                end
                S_CNN_CMD: begin
                    if (app_rdy) begin
                        app_addr <= cnn_rd_addr;
                        app_cmd  <= CMD_READ;
                        app_en   <= 1'b1;
                        rd_owner <= RD_CNN;
                        state    <= S_CNN_WAIT;
                    end
                end
                S_CNN_WAIT: begin
                    if (app_rd_data_valid) begin
                        cnn_rd_data  <= app_rd_data;
                        cnn_rd_valid <= 1'b1;
                        state        <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule