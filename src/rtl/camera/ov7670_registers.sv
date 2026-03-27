// LUT of OV7670 register configurations.
// entries in format: {register_address, register_value}.

module ov7670_registers (
    input  logic [7:0]  index,    
    output logic [15:0] data
);
    // Register count (used by SCCB controller)
    localparam NUM_REGS = 8'd76;

    always_comb begin
        case (index)
            8'd0:  data = {8'h12, 8'h80};   
            8'd1:  data = {8'hFF, 8'hFF};
            8'd2:  data = {8'h12, 8'h04}; // RGB output mode
            8'd3:  data = {8'h40, 8'hD0};  
            8'd4:  data = {8'h8C, 8'h00};  
            8'd5:  data = {8'h04, 8'h00};  
            8'd6:  data = {8'h3A, 8'h04};   
            8'd7:  data = {8'h3D, 8'h88};  
            8'd8:  data = {8'h11, 8'h01}; // prescaler divide by 2
            8'd9:  data = {8'h0C, 8'h00};  
            8'd10: data = {8'h3E, 8'h00};
            8'd11: data = {8'h17, 8'h13};   
            8'd12: data = {8'h18, 8'h01};  
            8'd13: data = {8'h32, 8'hB6};  
            8'd14: data = {8'h19, 8'h02};  
            8'd15: data = {8'h1A, 8'h7A};   
            8'd16: data = {8'h03, 8'h0A};
            8'd17: data = {8'h14, 8'h18};  
            8'd18: data = {8'h13, 8'hE0};   
            8'd19: data = {8'h00, 8'h00};   
            8'd20: data = {8'h10, 8'h00}; 
            8'd21: data = {8'h07, 8'h00}; 
            8'd22: data = {8'h01, 8'h80}; 
            8'd23: data = {8'h02, 8'h80};  
            8'd24: data = {8'h6A, 8'h40};  
            8'd25: data = {8'h4F, 8'h80};   
            8'd26: data = {8'h50, 8'h80};   
            8'd27: data = {8'h51, 8'h00};   
            8'd28: data = {8'h52, 8'h22};  
            8'd29: data = {8'h53, 8'h5E};   
            8'd30: data = {8'h54, 8'h80};   
            8'd31: data = {8'h58, 8'h9E};  
            8'd32: data = {8'h7A, 8'h20};  
            8'd33: data = {8'h7B, 8'h10};   
            8'd34: data = {8'h7C, 8'h1E};  
            8'd35: data = {8'h7D, 8'h35};   
            8'd36: data = {8'h7E, 8'h5A}; 
            8'd37: data = {8'h7F, 8'h69};  
            8'd38: data = {8'h80, 8'h76};  
            8'd39: data = {8'h81, 8'h80};   
            8'd40: data = {8'h82, 8'h88};  
            8'd41: data = {8'h83, 8'h8F};
            8'd42: data = {8'h84, 8'h96};  
            8'd43: data = {8'h85, 8'hA3};  
            8'd44: data = {8'h86, 8'hAF}; 
            8'd45: data = {8'h87, 8'hC4};   
            8'd46: data = {8'h88, 8'hD7};  
            8'd47: data = {8'h89, 8'hE8}; 
            8'd48: data = {8'h43, 8'h0A};   
            8'd49: data = {8'h44, 8'hF0}; 
            8'd50: data = {8'h45, 8'h34}; 
            8'd51: data = {8'h46, 8'h58};  
            8'd52: data = {8'h47, 8'h28};  
            8'd53: data = {8'h48, 8'h3A}; 
            8'd54: data = {8'h59, 8'h88};  
            8'd55: data = {8'h5A, 8'h88};
            8'd56: data = {8'h5B, 8'h44};
            8'd57: data = {8'h5C, 8'h67};
            8'd58: data = {8'h5D, 8'h49};
            8'd59: data = {8'h5E, 8'h0E};
            8'd60: data = {8'h6C, 8'h0A}; 
            8'd61: data = {8'h6D, 8'h55}; 
            8'd62: data = {8'h6E, 8'h11};
            8'd63: data = {8'h6F, 8'h9F};
            8'd64: data = {8'h3F, 8'h00};  
            8'd65: data = {8'h75, 8'h05}; 
            8'd66: data = {8'h76, 8'hE1};   
            8'd67: data = {8'h4C, 8'h00};   
            8'd68: data = {8'h77, 8'h01}; 
            8'd69: data = {8'h69, 8'h00}; 
            8'd70: data = {8'h41, 8'h18};
            8'd71: data = {8'h4D, 8'h40}; 
            8'd72: data = {8'h4E, 8'h20};  
            8'd73: data = {8'h74, 8'h10}; 
            8'd74: data = {8'hB1, 8'h0C}; 
            8'd75: data = {8'hFE, 8'hFE};  
            default: data = {8'hFE, 8'hFE};
        endcase
    end

endmodule