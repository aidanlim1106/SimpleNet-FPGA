// SCCB (Serial Camera Control Bus) master
//
// SCCB is basically I2C with minor differences:
//   - No clock stretching
//   - No multi-master
//   - ACK bit is "don't care" (camera may or may not ACK)


module ov7670_sccb (
    input clk, // 24 mHz system clock
    input rst,

    // Control interface
    input start,     
    output logic done,     

    // SCCB physical pins
    output logic sioc,  // serial clock
    output logic siod_out, 
    output logic siod_oe, // state control (1=drive, 0=high-Z)
    input siod_in
);

    localparam CAMERA_ADDR = 8'h42;    
    localparam CLK_DIV     = 10'd240;  
    localparam HALF_CLK    = 10'd120;    /
    localparam NUM_REGS    = 8'd76;
    logic [7:0]  reg_index;
    logic [15:0] reg_data;          
    logic [7:0]  current_reg_addr;
    logic [7:0]  current_reg_val;

    ov7670_registers u_regs (
        .index (reg_index),
        .data  (reg_data)
    );

    assign current_reg_addr = reg_data[15:8];
    assign current_reg_val  = reg_data[7:0];
    logic [9:0] clk_count;
    logic       clk_tick;        

    always_ff @(posedge clk) begin
        if (rst) begin
            clk_count <= 10'd0;
        end else begin
            if (clk_count == CLK_DIV - 1)
                clk_count <= 10'd0;
            else
                clk_count <= clk_count + 10'd1;
        end
    end

    logic tick_rising;   
    logic tick_falling;  
    assign tick_rising  = (clk_count == 10'd0);
    assign tick_falling = (clk_count == HALF_CLK);

    typedef enum logic [3:0] {
        S_IDLE,           // Waiting for start
        S_LOAD,           // Load next register from LUT
        S_CHECK,          // Check for delay or end marker
        S_START_A,        // Generate START condition (SDA low while SCL high)
        S_START_B,        // SCL goes low after start
        S_SEND_BIT,       // Clock out one bit
        S_SEND_ACK,       // Release SDA for ACK clock
        S_STOP_A,         // Generate STOP (SDA low while SCL low)
        S_STOP_B,         // SCL goes high
        S_STOP_C,         // SDA goes high while SCL high = STOP
        S_DELAY,          // Wait after reset command
        S_NEXT,           // Advance to next register
        S_DONE            // All registers programmed
    } state_t;

    state_t state;
    logic [23:0] tx_shift;     // 24-bit shift register: {addr, reg, val}
    logic [4:0]  bit_count; 
    logic [1:0]  byte_count;   // (0, 1, 2)
    logic [3:0]  bits_in_byte; // Count within current byte (0–8)
    logic [19:0] delay_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            reg_index   <= 8'd0;
            sioc        <= 1'b1;
            siod_out    <= 1'b1;
            siod_oe     <= 1'b1;
            done        <= 1'b0;
            bit_count   <= 5'd0;
            byte_count  <= 2'd0;
            bits_in_byte <= 4'd0;
            delay_count <= 20'd0;
        end else begin

            case (state)
                S_IDLE: begin
                    sioc     <= 1'b1;
                    siod_out <= 1'b1;
                    siod_oe  <= 1'b1;
                    if (start && !done) begin
                        reg_index <= 8'd0;
                        state     <= S_LOAD;
                    end
                end
                // LOAD: Read register from LUT
                S_LOAD: begin
                    state <= S_CHECK;
                end
                S_CHECK: begin
                    if (current_reg_addr == 8'hFE) begin
                        state <= S_DONE;
                    end else if (current_reg_addr == 8'hFF) begin
                        delay_count <= 20'd240_000;  
                        state       <= S_DELAY;
                    end else begin
                        tx_shift     <= {CAMERA_ADDR, current_reg_addr, current_reg_val};
                        byte_count   <= 2'd0;
                        bits_in_byte <= 4'd0;
                        state        <= S_START_A;
                    end
                end
                S_START_A: begin
                    if (tick_falling) begin
                        sioc     <= 1'b1;   
                        siod_out <= 1'b0;   
                        siod_oe  <= 1'b1;   
                        state    <= S_START_B;
                    end
                end

                S_START_B: begin
                    if (tick_falling) begin
                        sioc  <= 1'b0;     
                        state <= S_SEND_BIT;
                    end
                end
                // SEND BITS: MSB first, 8 bits then ACK
                S_SEND_BIT: begin
                    if (tick_falling) begin
                        siod_out <= tx_shift[23]; 
                        siod_oe  <= 1'b1;
                        sioc     <= 1'b0;
                    end
                    if (tick_rising) begin
                        sioc <= 1'b1;
                        tx_shift     <= {tx_shift[22:0], 1'b0};  
                        bits_in_byte <= bits_in_byte + 4'd1;

                        if (bits_in_byte == 4'd7) begin
                            state <= S_SEND_ACK;
                        end
                    end
                end
                // ACK: Release SDA, clock once (camera may pull low)
                S_SEND_ACK: begin
                    if (tick_falling) begin
                        siod_oe <= 1'b0;    
                        sioc    <= 1'b0;
                    end
                    if (tick_rising) begin
                        sioc <= 1'b1;
                        bits_in_byte <= 4'd0;
                        byte_count   <= byte_count + 2'd1;

                        if (byte_count == 2'd2) begin
                            state <= S_STOP_A;
                        end else begin
                            state <= S_SEND_BIT;
                        end
                    end
                end
                S_STOP_A: begin
                    if (tick_falling) begin
                        siod_out <= 1'b0;  
                        siod_oe  <= 1'b1;
                        sioc     <= 1'b0;   
                        state    <= S_STOP_B;
                    end
                end
                S_STOP_B: begin
                    if (tick_rising) begin
                        sioc <= 1'b1;    
                        state <= S_STOP_C;
                    end
                end
                S_STOP_C: begin
                    if (tick_falling) begin
                        siod_out <= 1'b1;   
                        state    <= S_NEXT;
                    end
                end
                S_DELAY: begin
                    if (delay_count == 20'd0) begin
                        state <= S_NEXT;
                    end else begin
                        delay_count <= delay_count - 20'd1;
                    end
                end
                S_NEXT: begin
                    reg_index <= reg_index + 8'd1;
                    state     <= S_LOAD;
                end
                S_DONE: begin
                    done <= 1'b1;
                end

            endcase
        end
    end

endmodule