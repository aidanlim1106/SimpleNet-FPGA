// verify MMCM clock wizard is generating correct 24mhz frequency
// Board: Real Digital Urbana (Spartan-7 XC7S50)

module top_clk_test (
    input wire sys_clk,
    output logic led
);

    logic clk_24mhz;
    logic clk_25mhz;
    logic locked;
    logic rst;

    assign rst = ~locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1 (sys_clk),
        .clk_out1 (clk_24mhz),
        .clk_out2 (clk_25mhz),
        .reset (1'b0),
        .locked (locked)
    );

    logic [24:0] counter;
    logic led_state;

    always_ff @(posedge clk_24mhz) begin
        if (rst) begin
            counter   <= 25'd0;
            led_state <= 1'b0;
        end else begin
            if (counter == 25'd23_999_999) begin
                counter   <= 25'd0;
                led_state <= ~led_state;
            end else begin
                counter   <= counter + 25'd1;
            end
        end
    end

    assign led = led_state;

endmodule