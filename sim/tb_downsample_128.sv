`timescale 1ns / 1ps

module tb_downsample_128;

    logic pclk = 0;
    always #42 pclk = ~pclk;

    logic rst;
    logic [15:0] pixel_data;
    logic pixel_valid;
    logic [9:0] pixel_col;
    logic [8:0] pixel_row;
    logic frame_start;
    logic [7:0] ds_pixel_data;
    logic ds_pixel_valid;
    logic [13:0] ds_pixel_addr;

    downsample_128 u_dut (
        .pclk          (pclk),
        .rst           (rst),
        .pixel_data    (pixel_data),
        .pixel_valid   (pixel_valid),
        .pixel_col     (pixel_col),
        .pixel_row     (pixel_row),
        .frame_start   (frame_start),
        .ds_pixel_data (ds_pixel_data),
        .ds_pixel_valid(ds_pixel_valid),
        .ds_pixel_addr (ds_pixel_addr)
    );

    int ds_count;

    always_ff @(posedge pclk) begin
        if (ds_pixel_valid) begin
            ds_count <= ds_count + 1;
            if (ds_count < 20) begin
                $display("[%0t] DS pixel %0d: addr=%0d gray=%0d",
                         $time, ds_count, ds_pixel_addr, ds_pixel_data);
            end
        end
    end

    // Simulate one full 640×480 frame
    task send_full_frame();
        @(posedge pclk);
        frame_start <= 1'b1;
        @(posedge pclk);
        frame_start <= 1'b0;
        repeat (100) @(posedge pclk);
        // send all pixels
        for (int row = 0; row < 480; row++) begin
            for (int col = 0; col < 640; col++) begin
                @(posedge pclk);
                pixel_valid <= 1'b1;
                pixel_col   <= 10'(col);
                pixel_row   <= 9'(row);
                pixel_data  <= {row[7:3], col[7:2], row[4:0]};
            end
            @(posedge pclk);
            pixel_valid <= 1'b0;
            repeat (5) @(posedge pclk);
        end

        pixel_valid <= 1'b0;
    endtask

    initial begin
        rst         = 1'b1;
        pixel_data  = 16'd0;
        pixel_valid = 1'b0;
        pixel_col   = 10'd0;
        pixel_row   = 9'd0;
        frame_start = 1'b0;
        ds_count    = 0;

        #500;
        rst = 1'b0;
        #100;

        $display("\n[%0t] Sending full 640x480 frame...", $time);
        send_full_frame();

        #1000;
        $display("\n=============================");
        $display("  Total output pixels: %0d", ds_count);
        $display("  Expected:            %0d", 128 * 128);

        if (ds_count == 128 * 128)
            $display("  ✅ PIXEL COUNT CORRECT!");
        else
            $display("  ❌ PIXEL COUNT WRONG!");

        $display("=============================\n");
        $finish;
    end

    initial begin
        #200_000_000; 
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule