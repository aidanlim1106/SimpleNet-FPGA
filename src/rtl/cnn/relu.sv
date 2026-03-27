// ReLU activation + re-quantization

module relu (
    input signed [31:0] acc_in,    
    input [4:0] shift,    
    output logic [7:0] pixel_out  
);

    logic signed [31:0] shifted;
    
    always_comb begin
        shifted = acc_in >>> shift;
        // ReLU: clamp negative to 0
        if (shifted < 0) begin
            pixel_out = 8'd0;
        // Saturate: clamp above 255 to 255
        end else if (shifted > 255) begin
            pixel_out = 8'd255;
        end else begin
            pixel_out = shifted[7:0];
        end
    end

endmodule