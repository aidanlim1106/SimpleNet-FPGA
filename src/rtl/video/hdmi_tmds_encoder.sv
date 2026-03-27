
// encode 8-bit pixel data into 10-bit TMDS symbols
// approach:
//  ACTIVE video:
//   8 bits of color → 10 bits of TMDS
//   Uses XOR or XNOR to minimize transitions in bits [7:0]
//   Bit [8] tells receiver which operation was used
//   Bit [9] optionally inverts bits [7:0] for DC balance
//
//  BLANKING:
//   Sends one of four "control tokens" based on HSYNC/VSYNC:
//     {VSYNC, HSYNC} = 00 → 10'b1101010100
//     {VSYNC, HSYNC} = 01 → 10'b0010101011
//     {VSYNC, HSYNC} = 10 → 10'b0101010100
//     {VSYNC, HSYNC} = 11 → 10'b1010101011

module hdmi_tmds_encoder (
    input clk,           
    input rst,
    input [7:0] data_in,   
    input active, // HIGH = send pixel data
    input [1:0] ctrl,         

    output logic [9:0] tmds_out     
);

    logic [3:0] ones_count;

    always_comb begin
        ones_count = 4'd0;
        for (int i = 0; i < 8; i++) begin
            ones_count = ones_count + {3'b0, data_in[i]};
        end
    end

    // >= 4, use XNOR else XOR
    logic use_xnor;
    logic [8:0] q_m;   

    always_comb begin
        use_xnor = (ones_count > 4'd4) ||
                   (ones_count == 4'd4 && data_in[0] == 1'b0);
        q_m[0] = data_in[0];

        if (use_xnor) begin
            q_m[1] = ~(q_m[0] ^ data_in[1]);
            q_m[2] = ~(q_m[1] ^ data_in[2]);
            q_m[3] = ~(q_m[2] ^ data_in[3]);
            q_m[4] = ~(q_m[3] ^ data_in[4]);
            q_m[5] = ~(q_m[4] ^ data_in[5]);
            q_m[6] = ~(q_m[5] ^ data_in[6]);
            q_m[7] = ~(q_m[6] ^ data_in[7]);
            q_m[8] = 1'b0;
        end else begin
            q_m[1] = q_m[0] ^ data_in[1];
            q_m[2] = q_m[1] ^ data_in[2];
            q_m[3] = q_m[2] ^ data_in[3];
            q_m[4] = q_m[3] ^ data_in[4];
            q_m[5] = q_m[4] ^ data_in[5];
            q_m[6] = q_m[5] ^ data_in[6];
            q_m[7] = q_m[6] ^ data_in[7];
            q_m[8] = 1'b1;
        end
    end

    // Step 3: DC balance tracking
    // If disparity/difference is getting too positive, we send more 0s
    // If too negative, send more 1s
    logic signed [4:0] disparity; 

    // count 1s in q_m[7:0]
    logic [3:0] q_m_ones;
    always_comb begin
        q_m_ones = 4'd0;
        for (int i = 0; i < 8; i++) begin
            q_m_ones = q_m_ones + {3'b0, q_m[i]};
        end
    end

    // final 10-bit TMDS output
    always_ff @(posedge clk) begin
        if (rst) begin
            tmds_out  <= 10'd0;
            disparity <= 5'sd0;
        end else begin
            if (!active) begin
                // sent control token
                disparity <= 5'sd0;   
                case (ctrl)
                    2'b00: tmds_out <= 10'b1101010100;
                    2'b01: tmds_out <= 10'b0010101011;
                    2'b10: tmds_out <= 10'b0101010100;
                    2'b11: tmds_out <= 10'b1010101011;
                endcase
            end else begin
                // Encode pixel data
                if (disparity == 5'sd0 || q_m_ones == 4'd4) begin
                    tmds_out[9]   <= ~q_m[8];
                    tmds_out[8]   <= q_m[8];
                    tmds_out[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                    if (q_m[8] == 1'b0) begin
                        disparity <= disparity +
                                     (5'sd4 - {1'b0, q_m_ones} -
                                      {1'b0, q_m_ones} + 5'sd4);
                    end else begin
                        disparity <= disparity +
                                     ({1'b0, q_m_ones} +
                                      {1'b0, q_m_ones} - 5'sd4 -
                                      5'sd4);
                    end
                end else begin
                    if ((disparity > 5'sd0 && q_m_ones > 4'd4) ||
                        (disparity < 5'sd0 && q_m_ones < 4'd4)) begin
                        tmds_out[9]   <= 1'b1;
                        tmds_out[8]   <= q_m[8];
                        tmds_out[7:0] <= ~q_m[7:0];
                        disparity <= disparity + {3'b0, q_m[8], 1'b0} +
                                     5'sd4 - {1'b0, q_m_ones} -
                                     {1'b0, q_m_ones} + 5'sd4;
                    end else begin
                        tmds_out[9]   <= 1'b0;
                        tmds_out[8]   <= q_m[8];
                        tmds_out[7:0] <= q_m[7:0];
                        disparity <= disparity - {3'b0, ~q_m[8], 1'b0} +
                                     {1'b0, q_m_ones} +
                                     {1'b0, q_m_ones} - 5'sd4 -
                                     5'sd4;
                    end
                end
            end
        end
    end

endmodule