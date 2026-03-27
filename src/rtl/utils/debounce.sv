// debounce a mechanical button input.


module debounce #(
    parameter CLK_FREQ = 24_000_000,  
    parameter STABLE_MS = 10
)(
    input clk,
    input rst,
    input btn_in,     
    output logic btn_out
);
    localparam COUNT_MAX = (CLK_FREQ / 1000) * STABLE_MS;
    localparam COUNT_BITS = $clog2(COUNT_MAX + 1);
    logic [COUNT_BITS-1:0] counter;
    logic btn_sync_0;
    logic btn_sync_1;

    always_ff @(posedge clk) begin
        if (rst) begin
            btn_sync_0 <= 1'b0;
            btn_sync_1 <= 1'b0;
        end else begin
            btn_sync_0 <= btn_in;
            btn_sync_1 <= btn_sync_0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            counter <= '0;
            btn_out <= 1'b0;
        end else begin
            if (btn_sync_1 != btn_out) begin
                if (counter == COUNT_MAX - 1) begin
                    btn_out <= btn_sync_1;  
                    counter <= '0;
                end else begin
                    counter <= counter + 1;
                end
            end else begin
                counter <= '0;
            end
        end
    end

endmodule