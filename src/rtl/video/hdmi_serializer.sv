// serialize 10-bit TMDS symbols into a differential pair using Xilinx OSERDESE2 primitives.

module hdmi_serializer (
    input pixel_clk,     // 25 MHz
    input serial_clk,    // 125 MHz
    input rst,
    input [9:0] tmds_data,  
    output logic tmds_p, // diff pos
    output logic tmds_n // diff neg
);
    // OSERDESE2: Master + Slave cascade
    logic serial_out;    
    logic cascade_out1;  
    logic cascade_out2;

    // Master OSERDESE2
    OSERDESE2 #(
        .DATA_RATE_OQ  ("DDR"),      
        .DATA_RATE_TQ  ("SDR"),      
        .DATA_WIDTH    (10),          
        .SERDES_MODE   ("MASTER"),   
        .TRISTATE_WIDTH(1)
    ) u_master (
        .OQ       (serial_out),      
        .OFB      (),             
        .TQ       (),               
        .TFB      (),               
        .SHIFTOUT1(cascade_out1),     
        .SHIFTOUT2(cascade_out2),    
        .CLK      (serial_clk),      
        .CLKDIV   (pixel_clk),     
        .D1       (tmds_data[0]),    
        .D2       (tmds_data[1]),
        .D3       (tmds_data[2]),
        .D4       (tmds_data[3]),
        .D5       (tmds_data[4]),
        .D6       (tmds_data[5]),
        .D7       (tmds_data[6]),
        .D8       (tmds_data[7]),  
        .TCE      (1'b0),         
        .OCE      (1'b1),         
        .TBYTEIN  (1'b0),          
        .TBYTEOUT (),
        .RST      (rst),
        .SHIFTIN1 (1'b0),         
        .SHIFTIN2 (1'b0),
        .T1       (1'b0),
        .T2       (1'b0),
        .T3       (1'b0),
        .T4       (1'b0)
    );

    // Slave OSERDESE2
    OSERDESE2 #(
        .DATA_RATE_OQ  ("DDR"),
        .DATA_RATE_TQ  ("SDR"),
        .DATA_WIDTH    (10),
        .SERDES_MODE   ("SLAVE"),   
        .TRISTATE_WIDTH(1)
    ) u_slave (
        .OQ       (),           
        .OFB      (),
        .TQ       (),
        .TFB      (),
        .SHIFTOUT1(),         
        .SHIFTOUT2(),
        .CLK      (serial_clk),
        .CLKDIV   (pixel_clk),
        .D1       (1'b0),         
        .D2       (1'b0),
        .D3       (tmds_data[8]),  
        .D4       (tmds_data[9]),  
        .D5       (1'b0),
        .D6       (1'b0),
        .D7       (1'b0),
        .D8       (1'b0),
        .TCE      (1'b0),
        .OCE      (1'b1),
        .TBYTEIN  (1'b0),
        .TBYTEOUT (),
        .RST      (rst),
        .SHIFTIN1 (cascade_out1),   
        .SHIFTIN2 (cascade_out2),   
        .T1       (1'b0),
        .T2       (1'b0),
        .T3       (1'b0),
        .T4       (1'b0)
    );

    // OBUFDS: Single-ended -> Differential
    OBUFDS #(
        .IOSTANDARD ("TMDS_33")
    ) u_obufds (
        .O  (tmds_p),             
        .OB (tmds_n),               
        .I  (serial_out)         
    );

endmodule