// multiply-accumulate operation
// pixel (uint8) × weight (int8) + accumulator

module mac_unit (
    input clk,
    input rst,
    input clear,        
    input enable,       
    input bias_load,  
    input [7:0] pixel,        
    input signed [7:0] weight, 
    input signed [15:0] bias,  
    output logic signed [31:0] acc    
);

    // need to extend pixel to signed
    logic signed [16:0] product;
    assign product = $signed({1'b0, pixel}) * weight;

    always_ff @(posedge clk) begin
        if (rst) begin
            acc <= 32'sd0;
        end else if (clear) begin
            acc <= 32'sd0;
        end else if (bias_load) begin
            acc <= {{16{bias[15]}}, bias};
        end else if (enable) begin
            acc <= acc + {{15{product[16]}}, product};
        end
    end

endmodule