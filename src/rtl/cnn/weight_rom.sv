// store all CNN weights and biases in BRAM

module weight_rom (
    input clk,
    input [10:0] w_addr, // 0–1619
    output logic signed [7:0] w_data,
    input [4:0] b_addr, // 0–28
    output logic signed [15:0] b_data,
    input [1:0] s_addr, // 0–3
    output logic [4:0] s_data
);

    logic signed [7:0] weights [0:1619];
    initial begin
        $readmemh("conv1_weights.mem", weights, 0, 35);
        $readmemh("conv2_weights.mem", weights, 36, 323);
        $readmemh("conv3_weights.mem", weights, 324, 1475);
        $readmemh("conv4_weights.mem", weights, 1476, 1619);
    end

    always_ff @(posedge clk) begin
        w_data <= weights[w_addr];
    end

    // Bias storage (signed 16-bit)
    logic signed [15:0] biases [0:28];

    initial begin
        $readmemh("all_biases.mem", biases, 0, 28);
    end

    always_ff @(posedge clk) begin
        b_data <= biases[b_addr];
    end

    // Shift storage (5-bit unsigned)
    logic [4:0] shifts [0:3];

    initial begin
        $readmemh("layer_shifts.mem", shifts, 0, 3);
    end

    always_ff @(posedge clk) begin
        s_data <= shifts[s_addr];
    end

endmodule