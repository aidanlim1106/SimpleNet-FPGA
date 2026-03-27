// Complete HDMI output module.
// HDMI has 4 TMDS channels:
//   Channel 0: Blue  + HSYNC/VSYNC (during blanking)
//   Channel 1: Green
//   Channel 2: Red
//   Channel 3: Pixel clock (fixed pattern: 1111100000)


module hdmi_top (
    input pixel_clk,      // 25 MHz
    input serial_clk,     // 125 MHz
    input rst,
    input [7:0] pixel_r,
    input [7:0] pixel_g,
    input [7:0] pixel_b,
    input active,
    input hsync,
    input vsync,

    // HDMI differential outputs
    output logic hdmi_clk_p,
    output logic hdmi_clk_n,
    output logic hdmi_d0_p, // Blue
    output logic hdmi_d0_n,
    output logic hdmi_d1_p, // Green
    output logic hdmi_d1_n,
    output logic hdmi_d2_p, // Red
    output logic hdmi_d2_n
);
    // TMDS Encoding (3 color channels)
    logic [9:0] tmds_blue;
    logic [9:0] tmds_green;
    logic [9:0] tmds_red;

    // Blue channel: carries sync during blanking
    hdmi_tmds_encoder u_enc_blue (
        .clk      (pixel_clk),
        .rst      (rst),
        .data_in  (pixel_b),
        .active   (active),
        .ctrl     ({vsync, hsync}),    
        .tmds_out (tmds_blue)
    );

    // Green channel
    hdmi_tmds_encoder u_enc_green (
        .clk      (pixel_clk),
        .rst      (rst),
        .data_in  (pixel_g),
        .active   (active),
        .ctrl     (2'b00),      
        .tmds_out (tmds_green)
    );

    // Red channel
    hdmi_tmds_encoder u_enc_red (
        .clk      (pixel_clk),
        .rst      (rst),
        .data_in  (pixel_r),
        .active   (active),
        .ctrl     (2'b00),        
        .tmds_out (tmds_red)
    );

    // Serialization (4 channels including clock)
    // Data channel 0: Blue
    hdmi_serializer u_ser_d0 (
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .rst        (rst),
        .tmds_data  (tmds_blue),
        .tmds_p     (hdmi_d0_p),
        .tmds_n     (hdmi_d0_n)
    );

    // Data channel 1: Green
    hdmi_serializer u_ser_d1 (
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .rst        (rst),
        .tmds_data  (tmds_green),
        .tmds_p     (hdmi_d1_p),
        .tmds_n     (hdmi_d1_n)
    );

    // Data channel 2: Red
    hdmi_serializer u_ser_d2 (
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .rst        (rst),
        .tmds_data  (tmds_red),
        .tmds_p     (hdmi_d2_p),
        .tmds_n     (hdmi_d2_n)
    );

    hdmi_serializer u_ser_clk (
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .rst        (rst),
        .tmds_data  (10'b1111100000),  // fixed clock pattern
        .tmds_p     (hdmi_clk_p),
        .tmds_n     (hdmi_clk_n)
    );

endmodule