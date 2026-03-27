`timescale 1ns / 1ps

module tb_async_fifo;
    logic wr_clk = 0;
    logic rd_clk = 0;
    always #4  wr_clk = ~wr_clk;    // 125 MHz write clock
    always #6  rd_clk = ~rd_clk;    // 83 MHz read clock

    logic wr_rst, rd_rst;
    logic wr_en, rd_en;
    logic [7:0] wr_data;
    logic [7:0] rd_data;
    logic wr_full, rd_empty;

    async_fifo #(
        .DATA_WIDTH (8),
        .ADDR_WIDTH (4)        
    ) u_dut (
        .wr_clk  (wr_clk),
        .wr_rst  (wr_rst),
        .wr_en   (wr_en),
        .wr_data (wr_data),
        .wr_full (wr_full),
        .rd_clk  (rd_clk),
        .rd_rst  (rd_rst),
        .rd_en   (rd_en),
        .rd_data (rd_data),
        .rd_empty(rd_empty)
    );

    initial begin
        wr_rst  = 1'b1;
        rd_rst  = 1'b1;
        wr_en   = 1'b0;
        rd_en   = 1'b0;
        wr_data = 8'd0;

        #100;
        wr_rst = 1'b0;
        rd_rst = 1'b0;
        #50;

        $display("[%0t] Writing 10 values...", $time);
        for (int i = 0; i < 10; i++) begin
            @(posedge wr_clk);
            wr_en   <= 1'b1;
            wr_data <= 8'(i * 11);  
        end
        @(posedge wr_clk);
        wr_en <= 1'b0;

        #100;
        $display("[%0t] Reading values...", $time);
        for (int i = 0; i < 10; i++) begin
            @(posedge rd_clk);
            if (!rd_empty) begin
                rd_en <= 1'b1;
                $display("[%0t]   Read: %0d (expected %0d)",
                         $time, rd_data, i * 11);
            end
        end
        @(posedge rd_clk);
        rd_en <= 1'b0;

        #50;
        @(posedge rd_clk);
        if (rd_empty)
            $display("[%0t] FIFO correctly shows empty!", $time);

        #100;
        $display("\n=== ASYNC FIFO TEST COMPLETE ===\n");
        $finish;
    end

    initial begin
        #5_000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule