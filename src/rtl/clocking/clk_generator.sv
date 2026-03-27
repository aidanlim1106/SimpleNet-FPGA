//   24 MHz  → Camera XCLK
//   25 MHz  → HDMI pixel clock
//   125 MHz → HDMI serializer (5× pixel clock)

module clk_generator (
    input sys_clk, // 100 Mhz
    output logic clk_24mhz,    
    output logic clk_25mhz,     
    output logic clk_125mhz,
    output logic rst_24mhz,
    output logic rst_25mhz,
    output logic rst_125mhz,
    output logic locked
);

    logic rst_async;
    assign rst_async = ~locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (sys_clk),
        .clk_out1 (clk_24mhz),
        .clk_out2 (clk_25mhz),
        .clk_out3 (clk_125mhz),
        .reset    (1'b0),
        .locked   (locked)
    );

    reset_sync u_rst_24 (
        .clk     (clk_24mhz),
        .rst_in  (rst_async),
        .rst_out (rst_24mhz)
    );

    reset_sync u_rst_25 (
        .clk     (clk_25mhz),
        .rst_in  (rst_async),
        .rst_out (rst_25mhz)
    );

    reset_sync u_rst_125 (
        .clk     (clk_125mhz),
        .rst_in  (rst_async),
        .rst_out (rst_125mhz)
    );

endmodule