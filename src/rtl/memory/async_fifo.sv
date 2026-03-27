module async_fifo #(
    parameter DATA_WIDTH = 128,
    parameter ADDR_WIDTH = 4  
)(
    input wr_clk,
    input wr_rst,
    input wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic wr_full,

    input rd_clk,
    input rd_rst,
    input rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic rd_empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;  
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH:0] wr_ptr_bin; 
    logic [ADDR_WIDTH:0] wr_ptr_gray;  
    logic [ADDR_WIDTH:0] rd_ptr_bin;   
    logic [ADDR_WIDTH:0] rd_ptr_gray;  
    logic [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;  
    logic [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;  

    function automatic logic [ADDR_WIDTH:0] bin_to_gray(
        input logic [ADDR_WIDTH:0] bin
    );
        return bin ^ (bin >> 1);
    endfunction

    always_ff @(posedge wr_clk) begin
        if (wr_rst) begin
            wr_ptr_bin  <= '0;
            wr_ptr_gray <= '0;
        end else if (wr_en && !wr_full) begin
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr_bin  <= wr_ptr_bin + 1;
            wr_ptr_gray <= bin_to_gray(wr_ptr_bin + 1);
        end
    end

    always_ff @(posedge wr_clk) begin
        if (wr_rst) begin
            rd_ptr_gray_sync1 <= '0;
            rd_ptr_gray_sync2 <= '0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    assign wr_full = (wr_ptr_gray == {
        ~rd_ptr_gray_sync2[ADDR_WIDTH],
        ~rd_ptr_gray_sync2[ADDR_WIDTH-1],
         rd_ptr_gray_sync2[ADDR_WIDTH-2:0]
    });

    always_ff @(posedge rd_clk) begin
        if (rd_rst) begin
            rd_ptr_bin  <= '0;
            rd_ptr_gray <= '0;
        end else if (rd_en && !rd_empty) begin
            rd_ptr_bin  <= rd_ptr_bin + 1;
            rd_ptr_gray <= bin_to_gray(rd_ptr_bin + 1);
        end
    end

    assign rd_data = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];

    always_ff @(posedge rd_clk) begin
        if (rd_rst) begin
            wr_ptr_gray_sync1 <= '0;
            wr_ptr_gray_sync2 <= '0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);

endmodule