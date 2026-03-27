// cnn_pipeline.sv
// Complete CNN inference engine
// Processes 128×128 grayscale input through 4 conv layers,
// outputs 8×8 heatmap → (x,y) detection coordinates.
//   - Ping-pong BRAM buffers (A/B)
//   - Single MAC reused for all layers
//   - Sequential pixel processing
//   - ~1.5M cycles ≈ 18ms at 83MHz ≈ 55 fps

module cnn_pipeline (
    input clk,
    input rst,

    input input_valid,
    input [7:0] input_pixel,
    input [13:0] input_addr,
    input input_done,

    input start,
    output logic busy,
    output logic done,

    output logic [9:0]  detect_x,
    output logic [9:0]  detect_y,
    output logic [7:0]  detect_conf
);

    // Layer configuration
    typedef struct packed {
        logic [6:0]  in_w;
        logic [6:0]  out_w;
        logic [4:0]  in_ch;
        logic [4:0]  out_ch;
        logic [10:0] w_base;
        logic [4:0]  b_base;
        logic [1:0]  layer_id;
    } layer_config_t;

    layer_config_t layer_cfg [0:3];

    initial begin
        layer_cfg[0] = '{7'd128, 7'd64,  5'd1,  5'd4,  11'd0,    5'd0,  2'd0};
        layer_cfg[1] = '{7'd64,  7'd32,  5'd4,  5'd8,  11'd36,   5'd4,  2'd1};
        layer_cfg[2] = '{7'd32,  7'd16,  5'd8,  5'd16, 11'd324,  5'd12, 2'd2};
        layer_cfg[3] = '{7'd16,  7'd8,   5'd16, 5'd1,  11'd1476, 5'd28, 2'd3};
    end

    // Dual-port BRAM buffers (ping-pong, max 16384 bytes each)
    logic [7:0] buf_a [0:16383];
    logic [7:0] buf_b [0:16383];

    logic [13:0] rd_addr;
    logic [7:0] rd_data;
    logic [13:0] wr_addr;
    logic [7:0] wr_data;
    logic wr_en;
    logic buf_select;    // 0: read A write B, 1: read B write A

    // Read port
    always_ff @(posedge clk) begin
        if (!buf_select)
            rd_data <= buf_a[rd_addr];
        else
            rd_data <= buf_b[rd_addr];
    end

    // Write port
    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (!buf_select)
                buf_b[wr_addr] <= wr_data;
            else
                buf_a[wr_addr] <= wr_data;
        end
    end

    // Initial image load -> buf_a
    always_ff @(posedge clk) begin
        if (input_valid) begin
            buf_a[input_addr] <= input_pixel;
        end
    end

    // Weight ROM
    logic [10:0]        w_addr;
    logic signed [7:0]  w_data;
    logic [4:0]         b_addr;
    logic signed [15:0] b_data;
    logic [1:0]         s_addr;
    logic [4:0]         s_data;

    weight_rom u_weights (
        .clk    (clk),
        .w_addr (w_addr),
        .w_data (w_data),
        .b_addr (b_addr),
        .b_data (b_data),
        .s_addr (s_addr),
        .s_data (s_data)
    );

    // MAC unit
    logic        mac_clear;
    logic        mac_enable;
    logic        mac_bias_load;
    logic [7:0]  mac_pixel;
    logic signed [7:0]  mac_weight;
    logic signed [15:0] mac_bias;
    logic signed [31:0] mac_acc;

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

    // ReLU
    logic [7:0] relu_out;
    logic [4:0] relu_shift;

    relu u_relu (
        .acc_in    (mac_acc),
        .shift     (relu_shift),
        .pixel_out (relu_out)
    );

    // FSM states
    typedef enum logic [3:0] {
        S_IDLE,
        S_LOAD_WAIT,
        S_LAYER_INIT,
        S_PIXEL_INIT,
        S_LOAD_BIAS,
        S_CALC_ADDR,
        S_READ_WAIT,
        S_MAC,
        S_NEXT_POS,
        S_WRITE_OUTPUT,
        S_NEXT_PIXEL,
        S_NEXT_LAYER,
        S_FIND_MAX,
        S_DONE
    } state_t;

    state_t state;

    // Loop counters
    logic [1:0]  cur_layer;
    logic [4:0]  cur_out_ch;
    logic [6:0]  cur_out_y;
    logic [6:0]  cur_out_x;
    logic [4:0]  cur_in_ch;
    logic [1:0]  cur_kr;        // kernel row (0–2)
    logic [1:0]  cur_kc;        // kernel col (0–2)

    layer_config_t cfg;         // latched at layer init

    logic signed [7:0] src_y;
    logic signed [7:0] src_x;

    // Address calc for stride-2 conv w/ padding 1
    logic        pad_zero;
    logic [13:0] src_addr;

    always_comb begin
        src_y = $signed({1'b0, cur_out_y}) * 2 + $signed({1'b0, cur_kr}) - 1;
        src_x = $signed({1'b0, cur_out_x}) * 2 + $signed({1'b0, cur_kc}) - 1;

        pad_zero = (src_y < 0) || (src_y >= $signed({1'b0, cfg.in_w})) ||
                   (src_x < 0) || (src_x >= $signed({1'b0, cfg.in_w}));

        case (cfg.in_w)
            7'd128:  src_addr = {cur_in_ch[0],   src_y[6:0], src_x[6:0]};
            7'd64:   src_addr = {cur_in_ch[1:0], src_y[5:0], src_x[5:0]};
            7'd32:   src_addr = {cur_in_ch[2:0], src_y[4:0], src_x[4:0]};
            7'd16:   src_addr = {cur_in_ch[3:0], src_y[3:0], src_x[3:0]};
            default: src_addr = 14'd0;
        endcase
    end

    // Weight address
    logic [10:0] weight_addr;

    always_comb begin
        weight_addr = cfg.w_base +
                      {6'b0, cur_out_ch} * (cfg.in_ch * 9) +
                      {6'b0, cur_in_ch} * 11'd9 +
                      {9'b0, cur_kr} * 11'd3 +
                      {9'b0, cur_kc};
    end

    // Output write address
    logic [13:0] out_addr;
    always_comb begin
        case (cfg.out_w)
            7'd64:   out_addr = {cur_out_ch[1:0], cur_out_y[5:0], cur_out_x[5:0]};
            7'd32:   out_addr = {cur_out_ch[2:0], cur_out_y[4:0], cur_out_x[4:0]};
            7'd16:   out_addr = {cur_out_ch[3:0], cur_out_y[3:0], cur_out_x[3:0]};
            7'd8:    out_addr = {cur_out_ch[0],   cur_out_y[2:0], cur_out_x[2:0]};
            default: out_addr = 14'd0;
        endcase
    end

    // Detection: find max in 8×8 output
    logic [5:0] scan_idx;
    logic [7:0] max_val;
    logic [2:0] max_x, max_y;

    // Main state machine
    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            mac_clear     <= 1'b0;
            mac_enable    <= 1'b0;
            mac_bias_load <= 1'b0;
            wr_en         <= 1'b0;
            buf_select    <= 1'b0;
            detect_x      <= 10'd0;
            detect_y      <= 10'd0;
            detect_conf   <= 8'd0;
        end else begin
            mac_clear     <= 1'b0;
            mac_enable    <= 1'b0;
            mac_bias_load <= 1'b0;
            wr_en         <= 1'b0;
            done          <= 1'b0;

            case (state)

                S_IDLE: begin
                    busy <= 1'b0;
                    if (start && input_done) begin
                        busy       <= 1'b1;
                        cur_layer  <= 2'd0;
                        buf_select <= 1'b0;
                        state      <= S_LAYER_INIT;
                    end
                end

                S_LAYER_INIT: begin
                    cfg        <= layer_cfg[cur_layer];
                    cur_out_ch <= 5'd0;
                    cur_out_y  <= 7'd0;
                    cur_out_x  <= 7'd0;
                    s_addr     <= cur_layer;
                    state      <= S_PIXEL_INIT;
                end

                S_PIXEL_INIT: begin
                    cur_in_ch  <= 5'd0;
                    cur_kr     <= 2'd0;
                    cur_kc     <= 2'd0;
                    mac_clear  <= 1'b1;
                    relu_shift <= s_data;
                    b_addr     <= cfg.b_base + cur_out_ch;
                    state      <= S_LOAD_BIAS;
                end

                S_LOAD_BIAS: begin
                    mac_bias      <= b_data;
                    mac_bias_load <= 1'b1;
                    state         <= S_CALC_ADDR;
                end

                S_CALC_ADDR: begin
                    rd_addr <= src_addr;
                    w_addr  <= weight_addr;
                    state   <= S_READ_WAIT;
                end

                S_READ_WAIT: begin
                    state <= S_MAC;
                end

                S_MAC: begin
                    mac_pixel  <= pad_zero ? 8'd0 : rd_data;
                    mac_weight <= w_data;
                    mac_enable <= 1'b1;
                    state      <= S_NEXT_POS;
                end

                S_NEXT_POS: begin
                    if (cur_kc < 2'd2) begin
                        cur_kc <= cur_kc + 2'd1;
                        state  <= S_CALC_ADDR;
                    end else if (cur_kr < 2'd2) begin
                        cur_kc <= 2'd0;
                        cur_kr <= cur_kr + 2'd1;
                        state  <= S_CALC_ADDR;
                    end else if (cur_in_ch < cfg.in_ch - 1) begin
                        cur_kc    <= 2'd0;
                        cur_kr    <= 2'd0;
                        cur_in_ch <= cur_in_ch + 5'd1;
                        state     <= S_CALC_ADDR;
                    end else begin
                        state <= S_WRITE_OUTPUT;
                    end
                end

                S_WRITE_OUTPUT: begin
                    if (cur_layer == 2'd3) begin
                        wr_data <= (mac_acc >>> relu_shift) > 0 ?
                                   ((mac_acc >>> relu_shift) > 255 ? 8'd255 :
                                    mac_acc[7:0]) : 8'd0;
                    end else begin
                        wr_data <= relu_out;
                    end
                    wr_addr <= out_addr;
                    wr_en   <= 1'b1;
                    state   <= S_NEXT_PIXEL;
                end

                S_NEXT_PIXEL: begin
                    if (cur_out_x < cfg.out_w - 1) begin
                        cur_out_x <= cur_out_x + 7'd1;
                        state     <= S_PIXEL_INIT;
                    end else if (cur_out_y < cfg.out_w - 1) begin
                        cur_out_x <= 7'd0;
                        cur_out_y <= cur_out_y + 7'd1;
                        state     <= S_PIXEL_INIT;
                    end else if (cur_out_ch < cfg.out_ch - 1) begin
                        cur_out_x  <= 7'd0;
                        cur_out_y  <= 7'd0;
                        cur_out_ch <= cur_out_ch + 5'd1;
                        state      <= S_PIXEL_INIT;
                    end else begin
                        state <= S_NEXT_LAYER;
                    end
                end

                S_NEXT_LAYER: begin
                    buf_select <= ~buf_select;
                    if (cur_layer < 2'd3) begin
                        cur_layer <= cur_layer + 2'd1;
                        state     <= S_LAYER_INIT;
                    end else begin
                        scan_idx <= 6'd0;
                        max_val  <= 8'd0;
                        max_x   <= 3'd0;
                        max_y   <= 3'd0;
                        state    <= S_FIND_MAX;
                    end
                end

                S_FIND_MAX: begin
                    rd_addr <= {8'd0, scan_idx};
                    if (scan_idx > 6'd0) begin
                        if (rd_data > max_val) begin
                            max_val <= rd_data;
                            max_x   <= scan_idx[2:0] - 3'd1;
                            max_y   <= scan_idx[5:3];
                        end
                    end
                    if (scan_idx == 6'd63) begin
                        state <= S_DONE;
                    end else begin
                        scan_idx <= scan_idx + 6'd1;
                    end
                end

                S_DONE: begin
                    detect_x    <= {3'b0, max_x} * 10'd80 + 10'd40;
                    detect_y    <= {3'b0, max_y} * 10'd60 + 10'd30;
                    detect_conf <= max_val;
                    done        <= 1'b1;
                    state       <= S_IDLE;
                end

            endcase
        end
    end

endmodule