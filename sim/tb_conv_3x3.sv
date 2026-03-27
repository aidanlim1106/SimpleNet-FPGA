`timescale 1ns / 1ps

module tb_conv_3x3;
    logic clk;
    logic rst;
    initial clk = 0;
    always #5 clk = ~clk;
    logic mac_clear;
    logic mac_enable;
    logic mac_bias_load;
    logic [7:0] mac_pixel;
    logic signed [7:0] mac_weight;
    logic signed [15:0] mac_bias;
    logic signed [31:0] mac_acc;
    logic [4:0]  relu_shift;
    logic [7:0]  relu_out;

    mac_unit u_mac (
        .clk       (clk),
        .rst       (rst),
        .clear     (mac_clear),
        .enable    (mac_enable),
        .bias_load (mac_bias_load),
        .pixel     (mac_pixel),
        .weight    (mac_weight),
        .bias      (mac_bias),
        .acc       (mac_acc)
    );

    relu u_relu (
        .acc_in    (mac_acc),
        .shift     (relu_shift),
        .pixel_out (relu_out)
    );

    logic [7:0] test_pixels [0:8];   
    logic signed [7:0] test_weights [0:8];
    integer expected_acc;
    integer expected_shifted;
    integer expected_relu;
    integer i;
    integer pass_count;
    integer fail_count;

    // perform a full 3×3 convolution cycle
    task automatic do_conv_3x3(
        input [7:0] pixels [0:8],
        input signed [7:0] weights [0:8],
        input signed [15:0] bias,
        input [4:0] shift,
        input integer exp_acc,  
        input string test_name
    );
        integer exp_shifted, exp_relu;
        $display("\n--- Test: %s ---", test_name);
        // clear accumulator
        @(posedge clk);
        mac_clear <= 1'b1;
        mac_enable <= 1'b0;
        mac_bias_load <= 1'b0;
        @(posedge clk);
        mac_clear <= 1'b0;

        // load bias
        @(posedge clk);
        mac_bias <= bias;
        mac_bias_load <= 1'b1;
        @(posedge clk);
        mac_bias_load <= 1'b0;

        // feed 9 pixel×weight pairs
        for (i = 0; i < 9; i++) begin
            @(posedge clk);
            mac_pixel  <= pixels[i];
            mac_weight <= weights[i];
            mac_enable <= 1'b1;
            @(posedge clk);
            mac_enable <= 1'b0;
        end

        @(posedge clk);
        relu_shift <= shift;
        @(posedge clk);

        $display("  Accumulator: got %0d, expected %0d", mac_acc, exp_acc);
        if (mac_acc !== exp_acc) begin
            $display("  *** FAIL: accumulator mismatch ***");
            fail_count++;
        end else begin
            $display("  PASS: accumulator correct");
            pass_count++;
        end

        exp_shifted = exp_acc >>> shift;
        if (exp_shifted < 0)
            exp_relu = 0;
        else if (exp_shifted > 255)
            exp_relu = 255;
        else
            exp_relu = exp_shifted;

        $display("  ReLU output: got %0d, expected %0d (shifted=%0d)",
                 relu_out, exp_relu, exp_shifted);
        if (relu_out !== exp_relu[7:0]) begin
            $display("  *** FAIL: ReLU mismatch ***");
            fail_count++;
        end else begin
            $display("  PASS: ReLU correct");
            pass_count++;
        end

    endtask

    initial begin
        $display("============================================");
        $display("  tb_conv_3x3: Convolution Datapath Tests");
        $display("============================================");
        pass_count = 0;
        fail_count = 0;
        rst         = 1'b1;
        mac_clear   = 1'b0;
        mac_enable  = 1'b0;
        mac_bias_load = 1'b0;
        mac_pixel   = 8'd0;
        mac_weight  = 8'sd0;
        mac_bias    = 16'sd0;
        relu_shift  = 5'd0;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // TEST 1: All ones — simple identity check
        // pixels = all 1, weights = all 1, bias = 0
        // Expected: 1×1×9 + 0 = 9
        for (i = 0; i < 9; i++) begin
            test_pixels[i]  = 8'd1;
            test_weights[i] = 8'sd1;
        end
        do_conv_3x3(test_pixels, test_weights, 16'sd0, 5'd0, 9, "All-ones identity");

        // TEST 2: Known values with bias
        // pixels = {10,20,30, 40,50,60, 70,80,90}
        // weights = all 1
        // bias = 100
        // Expected: (10+20+30+40+50+60+70+80+90) + 100 = 550
        test_pixels[0] = 8'd10;  test_pixels[1] = 8'd20;  test_pixels[2] = 8'd30;
        test_pixels[3] = 8'd40;  test_pixels[4] = 8'd50;  test_pixels[5] = 8'd60;
        test_pixels[6] = 8'd70;  test_pixels[7] = 8'd80;  test_pixels[8] = 8'd90;
        for (i = 0; i < 9; i++) test_weights[i] = 8'sd1;
        do_conv_3x3(test_pixels, test_weights, 16'sd100, 5'd0, 550,
                     "Ascending pixels + bias");

        // TEST 3: With right-shift (re-quantization)
        // Same as test 2 but shift=2 → 550 >> 2 = 137
        do_conv_3x3(test_pixels, test_weights, 16'sd100, 5'd2, 550,
                     "Ascending pixels + shift=2");

        // TEST 4: Negative weights → negative accumulator → ReLU clamps to 0
        // pixels = all 128, weights = all -1, bias = 0
        // Expected acc: 128 × (-1) × 9 = -1152, ReLU → 0
        for (i = 0; i < 9; i++) begin
            test_pixels[i]  = 8'd128;
            test_weights[i] = -8'sd1;
        end
        do_conv_3x3(test_pixels, test_weights, 16'sd0, 5'd0, -1152,
                     "Negative weights → ReLU clamp");

        // TEST 5: Saturation test — large positive result
        // pixels = all 255, weights = all 127, bias = 0
        // Expected acc: 255 × 127 × 9 = 291,465
        // Shifted by 10: 291465 >> 10 = 284 → clamped to 255
        for (i = 0; i < 9; i++) begin
            test_pixels[i]  = 8'd255;
            test_weights[i] = 8'sd127;
        end
        do_conv_3x3(test_pixels, test_weights, 16'sd0, 5'd10, 291465,
                     "Saturation test (clamp 255)");

        // TEST 6: Zero-padding simulation
        // Only center pixel nonzero (simulating padded border)
        // pixels = {0,0,0, 0,200,0, 0,0,0}
        // weights = {1,2,3, 4,5,6, 7,8,9}
        // bias = 10
        // Expected: 200×5 + 10 = 1010
        for (i = 0; i < 9; i++) test_pixels[i] = 8'd0;
        test_pixels[4] = 8'd200;
        test_weights[0] = 8'sd1; test_weights[1] = 8'sd2; test_weights[2] = 8'sd3;
        test_weights[3] = 8'sd4; test_weights[4] = 8'sd5; test_weights[5] = 8'sd6;
        test_weights[6] = 8'sd7; test_weights[7] = 8'sd8; test_weights[8] = 8'sd9;
        do_conv_3x3(test_pixels, test_weights, 16'sd10, 5'd2, 1010,
                     "Zero-padded center pixel");

        // TEST 7: Negative bias pulling result negative
        // pixels = all 10, weights = all 1, bias = -200
        // Expected: 10×1×9 + (-200) = -110 → ReLU = 0
        for (i = 0; i < 9; i++) begin
            test_pixels[i]  = 8'd10;
            test_weights[i] = 8'sd1;
        end
        do_conv_3x3(test_pixels, test_weights, -16'sd200, 5'd0, -110,
                     "Negative bias → ReLU clamp");

        // TEST 8: Mixed positive/negative weights (edge detector kernel)
        // pixels = all 100
        // weights = {-1,-1,-1, -1,8,-1, -1,-1,-1} (Laplacian)
        // bias = 0
        // Expected: 100×(-1)×8 + 100×8 = -800+800 = 0
        for (i = 0; i < 9; i++) test_pixels[i] = 8'd100;
        test_weights[0] = -8'sd1; test_weights[1] = -8'sd1; test_weights[2] = -8'sd1;
        test_weights[3] = -8'sd1; test_weights[4] =  8'sd8; test_weights[5] = -8'sd1;
        test_weights[6] = -8'sd1; test_weights[7] = -8'sd1; test_weights[8] = -8'sd1;
        do_conv_3x3(test_pixels, test_weights, 16'sd0, 5'd0, 0,
                     "Laplacian on flat image");

        repeat (5) @(posedge clk);
        $display("\n============================================");
        $display("  RESULTS: %0d passed, %0d failed", pass_count, fail_count);
        $display("============================================");

        if (fail_count == 0)
            $display("  ALL TESTS PASSED!");
        else
            $display("  *** SOME TESTS FAILED ***");

        $finish;
    end

    initial begin
        #100_000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule