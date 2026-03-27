
// safely synchronize an asynchronous reset into target domain

module reset_sync (
    input clk,
    input logic rst_in,
    output logic rst_out
);
    logic rst_pipe_0;
    logic rst_pipe_1;

    always_ff @(posedge clk or posedge rst_in) begin
        if (rst_in) begin
            rst_pipe_0 <= 1'b1;
            rst_pipe_1 <= 1'b1;
        end else begin
            rst_pipe_0 <= 1'b0;
            rst_pipe_1 <= rst_pipe_0;
        end
    end

    assign rst_out = rst_pipe_1;

endmodule