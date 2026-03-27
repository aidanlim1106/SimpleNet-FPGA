// detects rising and falling edges

module edge_detect (
    input clk,
    input rst,
    input sig_in,
    output logic rise,
    output logic fall
);

    logic sig_prev;
    always_ff @(posedge clk) begin
        if (rst) begin
            sig_prev <= 1'b0;
        end else begin
            sig_prev <= sig_in;
        end
    end

    assign rise = sig_in & ~sig_prev;   
    assign fall = ~sig_in & sig_prev;

endmodule