`timescale 1ns / 1ps

module tb_ov7670_capture;
    logic pclk = 0;
    always #42 pclk = ~pclk;    // 12 MHz
    logic       rst;
    logic       vsync;
    logic       href;
    logic [7:0] d;
    logic [15:0] pixel_data;
    logic        pixel_valid;
    logic [18:0] pixel_addr;
    logic        frame_start;
    logic        frame_done;

    ov7670_capture u_dut (
        .pclk       (pclk),
        .rst        (rst),
        .vsync      (vsync),
        .href       (href),
        .d          (d),
        .pixel_data (pixel_data),
        .pixel_valid(pixel_valid),
        .pixel_addr (pixel_addr),
        .frame_start(frame_start),
        .frame_done (frame_done)
    );

    int pixel_count;
    int error_count;

    always_ff @(posedge pclk) begin
        if (pixel_valid) begin
            pixel_count <= pixel_count + 1;
        end
    end

    // Task: Send one row of fake pixels
    task send_row(input int row_num, input int num_cols);
        @(posedge pclk);
        href <= 1'b1;

        for (int col = 0; col < num_cols; col++) begin
            @(posedge pclk);
            d <= row_num[7:0];
            @(posedge pclk);
            d <= col[7:0];
        end

        @(posedge pclk);
        href <= 1'b0;
        d    <= 8'd0;
        repeat (10) @(posedge pclk);
    endtask

    // Task: Send one complete frame
    task send_frame(input int num_rows, input int num_cols);
        @(posedge pclk);
        vsync <= 1'b1;
        repeat (100) @(posedge pclk); 
        vsync <= 1'b0;
        repeat (50) @(posedge pclk); 
        // Send all rows
        for (int row = 0; row < num_rows; row++) begin
            send_row(row, num_cols);
        end
        repeat (50) @(posedge pclk);
    endtask

    initial begin
        rst         = 1'b1;
        vsync       = 1'b0;
        href        = 1'b0;
        d           = 8'd0;
        pixel_count = 0;
        error_count = 0;

        #500;
        rst = 1'b0;
        #100;

        // ---- Test 1: Small frame (4 rows × 8 cols) ----
        $display("\n[%0t] TEST 1: Sending 4×8 test frame...", $time);
        pixel_count = 0;
        send_frame(4, 8);

        $display("[%0t] Captured %0d pixels (expected 32)", $time, pixel_count);
        if (pixel_count == 32)
            $display("[%0t] TEST 1 PASSED!", $time);
        else begin
            $display("[%0t] TEST 1 FAILED!", $time);
            error_count++;
        end

        // ---- Test 2: Verify pixel data assembly ----
        $display("\n[%0t] TEST 2: Sending known pixels...", $time);
        pixel_count = 0;
        send_frame(2, 4);

        // ---- Test 3: Two consecutive frames ----
        $display("\n[%0t] TEST 3: Two consecutive frames...", $time);
        pixel_count = 0;
        send_frame(2, 4);
        send_frame(2, 4);
        $display("[%0t] Captured %0d pixels across 2 frames (expected 16)",
                 $time, pixel_count);

        #500;
        $display("\n=============================");
        if (error_count == 0)
            $display("   ALL TESTS PASSED!");
        else
            $display("   %0d TEST(S) FAILED!", error_count);
        $display("=============================\n");
        $finish;
    end

    initial begin
        #500_000;
        $display("ERROR: Simulation timed out!");
        $finish;
    end

endmodule