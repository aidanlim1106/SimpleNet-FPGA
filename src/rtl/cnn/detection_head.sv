// detection_head.sv
// Find (x,y) position of the maximum value in an 8×8 heatmap
// Converts grid coordinates to display coordinates.
// Can be used standalone or pipeline uses built-in S_FIND_MAX.

module detection_head (
    input clk,
    input rst,

    input start,
    output logic done,

    output logic [5:0] hm_addr,       // 0–63 (8×8)
    input [7:0] hm_data,

    output logic [9:0] detect_x,
    output logic [9:0] detect_y,
    output logic [7:0] detect_conf
);

    typedef enum logic [1:0] {
        DH_IDLE,
        DH_SCAN,
        DH_RESULT
    } state_t;

    state_t state;

    logic [5:0] scan_idx;
    logic [7:0] max_val;
    logic [2:0] max_x, max_y;

    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= DH_IDLE;
            done        <= 1'b0;
            detect_x    <= 10'd0;
            detect_y    <= 10'd0;
            detect_conf <= 8'd0;
        end else begin
            done <= 1'b0;

            case (state)
                DH_IDLE: begin
                    if (start) begin
                        scan_idx <= 6'd0;
                        max_val  <= 8'd0;
                        max_x    <= 3'd0;
                        max_y    <= 3'd0;
                        state    <= DH_SCAN;
                    end
                end

                DH_SCAN: begin
                    hm_addr <= scan_idx;
                    // Compare one cycle behind (BRAM latency)
                    if (scan_idx > 6'd0 && hm_data > max_val) begin
                        max_val <= hm_data;
                        max_x   <= scan_idx[2:0] - 3'd1;
                        max_y   <= scan_idx[5:3];
                    end
                    if (scan_idx == 6'd63) begin
                        state <= DH_RESULT;
                    end else begin
                        scan_idx <= scan_idx + 6'd1;
                    end
                end

                DH_RESULT: begin
                    detect_x    <= {3'b0, max_x} * 10'd80 + 10'd40;
                    detect_y    <= {3'b0, max_y} * 10'd60 + 10'd30;
                    detect_conf <= max_val;
                    done        <= 1'b1;
                    state       <= DH_IDLE;
                end
            endcase
        end
    end

endmodule