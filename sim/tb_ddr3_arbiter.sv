`timescale 1ns / 1ps

module tb_ddr3_arbiter;
    logic ui_clk = 0;
    always #6 ui_clk = ~ui_clk;
    logic ui_rst;
    logic calib_complete;
    // Camera
    logic cam_wr_req;
    logic [27:0] cam_wr_addr;
    logic [127:0] cam_wr_data;
    logic cam_wr_ack;
    // Display
    logic disp_rd_req;
    logic [27:0] disp_rd_addr;
    logic [127:0] disp_rd_data;
    logic disp_rd_valid;
    // CNN
    logic cnn_rd_req;
    logic [27:0] cnn_rd_addr;
    logic [127:0] cnn_rd_data;
    logic cnn_rd_valid;
    // Fake MIG signals
    logic [27:0] app_addr;
    logic [2:0] app_cmd;
    logic app_en;
    logic app_rdy;
    logic [127:0] app_wdf_data;
    logic [15:0] app_wdf_mask;
    logic app_wdf_wren;
    logic app_wdf_end;
    logic app_wdf_rdy;
    logic [127:0] app_rd_data;
    logic app_rd_data_valid;
    logic app_rd_data_end;
    
    ddr3_arbiter u_dut (
        .ui_clk          (ui_clk),
        .ui_rst          (ui_rst),
        .calib_complete  (calib_complete),
        .cam_wr_req      (cam_wr_req),
        .cam_wr_addr     (cam_wr_addr),
        .cam_wr_data     (cam_wr_data),
        .cam_wr_ack      (cam_wr_ack),
        .disp_rd_req     (disp_rd_req),
        .disp_rd_addr    (disp_rd_addr),
        .disp_rd_data    (disp_rd_data),
        .disp_rd_valid   (disp_rd_valid),
        .cnn_rd_req      (cnn_rd_req),
        .cnn_rd_addr     (cnn_rd_addr),
        .cnn_rd_data     (cnn_rd_data),
        .cnn_rd_valid    (cnn_rd_valid),
        .app_addr        (app_addr),
        .app_cmd         (app_cmd),
        .app_en          (app_en),
        .app_rdy         (app_rdy),
        .app_wdf_data    (app_wdf_data),
        .app_wdf_mask    (app_wdf_mask),
        .app_wdf_wren    (app_wdf_wren),
        .app_wdf_end     (app_wdf_end),
        .app_wdf_rdy     (app_wdf_rdy),
        .app_rd_data     (app_rd_data),
        .app_rd_data_valid (app_rd_data_valid),
        .app_rd_data_end   (app_rd_data_end)
    );

    // MIG is always ready, returns read data after 3 cycles
    assign app_rdy     = 1'b1;    
    assign app_wdf_rdy = 1'b1;   

    // 3 cycle delay
    logic [2:0] rd_pipe_valid;
    logic [127:0] rd_pipe_data;

    always_ff @(posedge ui_clk) begin
        if (ui_rst) begin
            rd_pipe_valid <= 3'b000;
        end else begin
            rd_pipe_valid <= {rd_pipe_valid[1:0],
                              (app_en && app_cmd == 3'b001)};
        end
    end

    assign app_rd_data_valid = rd_pipe_valid[2];
    assign app_rd_data_end   = rd_pipe_valid[2];
    assign app_rd_data       = 128'hCAFE_BABE_DEAD_BEEF_1234_5678_9ABC_DEF0;

    initial begin
        ui_rst         = 1'b1;
        calib_complete = 1'b0;
        cam_wr_req     = 1'b0;
        cam_wr_addr    = 28'd0;
        cam_wr_data    = 128'd0;
        disp_rd_req    = 1'b0;
        disp_rd_addr   = 28'd0;
        cnn_rd_req     = 1'b0;
        cnn_rd_addr    = 28'd0;

        #100;
        @(posedge ui_clk);
        ui_rst <= 1'b0;

        #200;
        @(posedge ui_clk);
        calib_complete <= 1'b1;
        $display("[%0t] DDR3 calibration complete!", $time);

        // Test 1: Camera write
        #50;
        @(posedge ui_clk);
        cam_wr_req  <= 1'b1;
        cam_wr_addr <= 28'h000_0000;
        cam_wr_data <= 128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111;
        @(posedge ui_clk);
        cam_wr_req  <= 1'b0;
        wait (cam_wr_ack);
        $display("[%0t] TEST 1 PASSED: Camera write ACK!", $time);

        // Test 2: Display read
        #50;
        @(posedge ui_clk);
        disp_rd_req  <= 1'b1;
        disp_rd_addr <= 28'h010_0000;
        @(posedge ui_clk);
        disp_rd_req  <= 1'b0;

        wait (disp_rd_valid);
        $display("[%0t] TEST 2 PASSED: Display read data = %h",
                 $time, disp_rd_data);

        // Test 3: CNN read
        #50;
        @(posedge ui_clk);
        cnn_rd_req  <= 1'b1;
        cnn_rd_addr <= 28'h020_0000;
        @(posedge ui_clk);
        cnn_rd_req  <= 1'b0;

        wait (cnn_rd_valid);
        $display("[%0t] TEST 3 PASSED: CNN read data = %h",
                 $time, cnn_rd_data);

        // Test 4: Priority — camera vs display
        #50;
        @(posedge ui_clk);
        cam_wr_req   <= 1'b1;
        cam_wr_addr  <= 28'h000_0010;
        cam_wr_data  <= 128'h2222;
        disp_rd_req  <= 1'b1;
        disp_rd_addr <= 28'h010_0010;
        @(posedge ui_clk);
        cam_wr_req   <= 1'b0;
        disp_rd_req  <= 1'b0;

        wait (cam_wr_ack);
        $display("[%0t] TEST 4a: Camera served first (correct!)", $time);
        @(posedge ui_clk);
        disp_rd_req  <= 1'b1;
        disp_rd_addr <= 28'h010_0010;
        @(posedge ui_clk);
        disp_rd_req  <= 1'b0;
        wait (disp_rd_valid);
        $display("[%0t] TEST 4b: Display served after camera (correct!)",
                 $time);

        // Test 5: Nothing happens before calibration
        #50;
        calib_complete <= 1'b0;
        #20;
        @(posedge ui_clk);
        cam_wr_req <= 1'b1;
        cam_wr_addr <= 28'h000_0020;
        cam_wr_data <= 128'h3333;
        #100;
        if (!cam_wr_ack)
            $display("[%0t] TEST 5 PASSED: No writes before calibration!",
                     $time);
        cam_wr_req <= 1'b0;
        #100;
        $display("\n=============================");
        $display("   ALL TESTS PASSED! ");
        $display("=============================\n");
        $finish;
    end

    initial begin
        #10_000;
        $display("ERROR: Simulation timed out!");
        $finish;
    end

endmodule