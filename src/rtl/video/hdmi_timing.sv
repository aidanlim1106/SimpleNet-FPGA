
// Generate 640×480 @ 60Hz video timing signals.
// HORIZONTAL (per line):
//   ├── 640 visible ──┤── 16 FP ──┤── 96 sync ──┤── 48 BP ──┤
//   Total: 800 pixel clocks per line
// VERTICAL (per frame):
//   ├── 480 visible ──┤── 10 FP ──┤── 2 sync ───┤── 33 BP ──┤
//   Total: 525 lines per frame
// Frame rate: 25,000,000 / (800 × 525) = 59.52 Hz ≈ 60 Hz


module hdmi_timing (
    input pixel_clk,   
    input rst,
    output logic hsync,       
    output logic vsync,        
    output logic active,    
    output logic [9:0] pixel_x,      
    output logic [9:0] pixel_y,   
    output logic hblank,       
    output logic vblank,        
    output logic frame_start    
);
    // Timing constants
    localparam H_VISIBLE = 10'd640;
    localparam H_FRONT   = 10'd16;
    localparam H_SYNC    = 10'd96;
    localparam H_BACK    = 10'd48;
    localparam H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;  // 800

    localparam V_VISIBLE = 10'd480;
    localparam V_FRONT   = 10'd10;
    localparam V_SYNC    = 10'd2;
    localparam V_BACK    = 10'd33;
    localparam V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;  // 525

    // counters
    logic [9:0] h_count;
    logic [9:0] v_count;

    always_ff @(posedge pixel_clk) begin
        if (rst) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // sync pulses
    always_ff @(posedge pixel_clk) begin
        if (rst) begin
            hsync <= 1'b0;
            vsync <= 1'b0;
        end else begin
            hsync <= (h_count >= H_VISIBLE + H_FRONT) &&
                     (h_count <  H_VISIBLE + H_FRONT + H_SYNC);
            vsync <= (v_count >= V_VISIBLE + V_FRONT) &&
                     (v_count <  V_VISIBLE + V_FRONT + V_SYNC);
        end
    end

    assign active = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    assign pixel_x = h_count;
    assign pixel_y = v_count[9:0];
    assign hblank = (h_count >= H_VISIBLE);
    assign vblank = (v_count >= V_VISIBLE);
    assign frame_start = (h_count == 10'd0) && (v_count == 10'd0);

endmodule