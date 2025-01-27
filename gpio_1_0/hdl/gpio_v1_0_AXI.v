// AXI4-lite GPIO IP implementation
// (gpio_v1_0_AXI.v)
// Jason Losh based on Xilinx IP tool auto-generated file
//
// Contains:
// AXI4-lite interface
// GPIO memory-mapped interface
// GPIO port interface and implemention
// GPIO interrupt generation

`timescale 1 ns / 1 ps

    module gpio_v1_0_AXI #
    (
        // Bit width of S_AXI address bus
        parameter integer C_S_AXI_ADDR_WIDTH = 5
    )
    (
        // Ports to top level module (what makes this the GPIO IP module)
        input wire [31:0] gpio_data_in,
        output wire [31:0] gpio_data_out,
        output wire [31:0] gpio_data_oe,
        output wire intr,

        // AXI clock and reset        
        input wire S_AXI_ACLK,
        input wire S_AXI_ARESETN,

        // AXI write channel
        // address:  add, protection, valid, ready
        // data:     data, byte enable strobes, valid, ready
        // response: response, valid, ready 
        input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
        input wire [2:0] S_AXI_AWPROT,
        input wire S_AXI_AWVALID,
        output wire S_AXI_AWREADY,
        
        input wire [31:0] S_AXI_WDATA,
        input wire [3:0] S_AXI_WSTRB,
        input wire S_AXI_WVALID,
        output wire  S_AXI_WREADY,
        
        output wire [1:0] S_AXI_BRESP,
        output wire S_AXI_BVALID,
        input wire S_AXI_BREADY,
        
        // AXI read channel
        // address: add, protection, valid, ready
        // data:    data, resp, valid, ready
        input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
        input wire [2:0] S_AXI_ARPROT,
        input wire S_AXI_ARVALID,
        output wire S_AXI_ARREADY,
        
        output wire [31:0] S_AXI_RDATA,
        output wire [1:0] S_AXI_RRESP,
        output wire S_AXI_RVALID,
        input wire S_AXI_RREADY
    );

    // Internal registers
    reg [31:0] latch_data;
    reg [31:0] out;
    reg [31:0] od;
    reg [31:0] int_enable;
    reg [31:0] int_positive;
    reg [31:0] int_negative;
    reg [31:0] int_edge_mode;
    reg [31:0] int_status;
    reg [31:0] int_clear_request;
    
    // Register map
    // ofs  fn
    //   0  data (r/w)
    //   4  out (r/w)
    //   8  od (r/w)
    //  12  int_enable (r/w)
    //  16  int_positive (r/w)
    //  20  int_negative (r/w)
    //  24  int_edge_mode (r/w)
    //  28  int_status_clear (r/w1c)
    
    // Register numbers
    localparam integer DATA_REG             = 3'b000;
    localparam integer OUT_REG              = 3'b001;
    localparam integer ODR_REG              = 3'b010;
    localparam integer INT_ENABLE_REG       = 3'b011;
    localparam integer INT_POSITIVE_REG     = 3'b100;
    localparam integer INT_NEGATIVE_REG     = 3'b101;
    localparam integer INT_EDGE_MODE_REG    = 3'b110;
    localparam integer INT_STATUS_CLEAR_REG = 3'b111;
    
    // AXI4-lite signals
    reg axi_awready;
    reg axi_wready;
    reg [1:0] axi_bresp;
    reg axi_bvalid;
    reg axi_arready;
    reg [31:0] axi_rdata;
    reg [1:0] axi_rresp;
    reg axi_rvalid;
    
    // friendly clock, reset, and bus signals from master
    wire axi_clk           = S_AXI_ACLK;
    wire axi_resetn        = S_AXI_ARESETN;
    wire [31:0] axi_awaddr = S_AXI_AWADDR;
    wire axi_awvalid       = S_AXI_AWVALID;
    wire axi_wvalid        = S_AXI_WVALID;
    wire [3:0] axi_wstrb   = S_AXI_WSTRB;
    wire axi_bready        = S_AXI_BREADY;
    wire [31:0] axi_araddr = S_AXI_ARADDR;
    wire axi_arvalid       = S_AXI_ARVALID;
    wire axi_rready        = S_AXI_RREADY;    
    
    // assign bus signals to master to internal reg names
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;
    
    // Handle gpio input metastability safely
    reg [31:0] read_port_data;
    reg [31:0] pre_read_port_data;
    always_ff @ (posedge(axi_clk))
    begin
        pre_read_port_data <= gpio_data_in;
        read_port_data <= pre_read_port_data;
    end

    // Assert address ready handshake (axi_awready) 
    // - after address is valid (axi_awvalid)
    // - after data is valid (axi_wvalid)
    // - while configured to receive a write (aw_en)
    // De-assert ready (axi_awready)
    // - after write response channel ready handshake received (axi_bready)
    // - after this module sends write response channel valid (axi_bvalid) 
    wire wr_add_data_valid = axi_awvalid && axi_wvalid;
    reg aw_en;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_awready <= 1'b0;
            aw_en <= 1'b1;
        end
        else
        begin
            if (wr_add_data_valid && ~axi_awready && aw_en)
            begin
                axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end
            else if (axi_bready && axi_bvalid)
                begin
                    aw_en <= 1'b1;
                    axi_awready <= 1'b0;
                end
            else           
                axi_awready <= 1'b0;
        end 
    end

    // Capture the write address (axi_awaddr) in the first clock (~axi_awready)
    // - after write address is valid (axi_awvalid)
    // - after write data is valid (axi_wvalid)
    // - while configured to receive a write (aw_en)
    reg [C_S_AXI_ADDR_WIDTH-1:0] waddr;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
            waddr <= 0;
        else if (wr_add_data_valid && ~axi_awready && aw_en)
            waddr <= axi_awaddr;
    end

    // Output write data ready handshake (axi_wready) generation for one clock
    // - after address is valid (axi_awvalid)
    // - after data is valid (axi_wvalid)
    // - while configured to receive a write (aw_en)
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
            axi_wready <= 1'b0;
        else
            axi_wready <= (wr_add_data_valid && ~axi_wready && aw_en);
    end       

    // Write data to internal registers
    // - after address is valid (axi_awvalid)
    // - after write data is valid (axi_wvalid)
    // - after this module asserts ready for address handshake (axi_awready)
    // - after this module asserts ready for data handshake (axi_wready)
    // write correct bytes in 32-bit word based on byte enables (axi_wstrb)
    // int_clear_request write is only active for one clock
    wire wr = wr_add_data_valid && axi_awready && axi_wready;
    integer byte_index;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            latch_data[31:0] <= 32'b0;
            out <= 32'b0;
            od <= 32'b0;
            int_enable <= 32'b0;
            int_positive <= 32'b0;
            int_negative <= 32'b0;
            int_edge_mode <= 32'b0;
            int_clear_request <= 32'b0;
        end 
        else 
        begin
            if (wr)
            begin
                case (axi_awaddr[4:2])
                    DATA_REG:
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if ( axi_wstrb[byte_index] == 1) 
                                latch_data[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    OUT_REG:
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
                                out[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    ODR_REG: 
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
                                od[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    INT_ENABLE_REG:
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
                                int_enable[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    INT_POSITIVE_REG:
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1) 
                                int_positive[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    INT_NEGATIVE_REG:
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
                                int_negative[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    INT_EDGE_MODE_REG:
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
                                int_edge_mode[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    INT_STATUS_CLEAR_REG:
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
                                int_clear_request[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                endcase
            end
            else
                int_clear_request <= 32'b0;
        end
    end    

    // Send write response (axi_bvalid, axi_bresp)
    // - after address is valid (axi_awvalid)
    // - after write data is valid (axi_wvalid)
    // - after this module asserts ready for address handshake (axi_awready)
    // - after this module asserts ready for data handshake (axi_wready)
    // Clear write response valid (axi_bvalid) after one clock
    wire wr_add_data_ready = axi_awready && axi_wready;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_bvalid  <= 0;
            axi_bresp   <= 2'b0;
        end 
        else
        begin    
            if (wr_add_data_valid && wr_add_data_ready && ~axi_bvalid)
            begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b0;
            end
            else if (S_AXI_BREADY && axi_bvalid) 
                axi_bvalid <= 1'b0; 
        end
    end   

    // In the first clock (~axi_arready) that the read address is valid
    // - capture the address (axi_araddr)
    // - output ready (axi_arready) for one clock
    reg [C_S_AXI_ADDR_WIDTH-1:0] raddr;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_arready <= 1'b0;
            raddr <= 32'b0;
        end 
        else
        begin    
            // if valid, pulse ready (axi_rready) for one clock and save address
            if (axi_arvalid && ~axi_arready)
            begin
                axi_arready <= 1'b1;
                raddr  <= axi_araddr;
            end
            else
                axi_arready <= 1'b0;
        end 
    end       
        
    // Update register read data
    // - after this module receives a valid address (axi_arvalid)
    // - after this module asserts ready for address handshake (axi_arready)
    // - before the module asserts the data is valid (~axi_rvalid)
    //   (don't change the data while asserting read data is valid)
    wire rd = axi_arvalid && axi_arready && ~axi_rvalid;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_rdata <= 32'b0;
        end 
        else
        begin    
            if (rd)
            begin
		// Address decoding for reading registers
		case (raddr[4:2])
		    DATA_REG: 
		        axi_rdata <= read_port_data;
		    OUT_REG:
		        axi_rdata <= out;
		    ODR_REG: 
		        axi_rdata <= od;
		    INT_ENABLE_REG: 
			axi_rdata <= int_enable;
		    INT_POSITIVE_REG:
			axi_rdata <= int_positive;
		    INT_NEGATIVE_REG:
			axi_rdata <= int_negative;
		    INT_EDGE_MODE_REG:
			axi_rdata <= int_edge_mode;
		    INT_STATUS_CLEAR_REG:
		        axi_rdata <= int_status;
		endcase
            end   
        end
    end    

    // Assert data is valid for reading (axi_rvalid)
    // - after address is valid (axi_arvalid)
    // - after this module asserts ready for address handshake (axi_arready)
    // De-assert data valid (axi_rvalid) 
    // - after master ready handshake is received (axi_rready)
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
            axi_rvalid <= 1'b0;
        else
        begin
            if (axi_arvalid && axi_arready && ~axi_rvalid)
            begin
                axi_rvalid <= 1'b1;
                axi_rresp <= 2'b0;
            end   
            else if (axi_rvalid && axi_rready)
                axi_rvalid <= 1'b0;
        end
    end    

    // pin control
    // OUT LATCH ODR   PIN
    //  0    x    x    hi-Z
    //  1    0    x     0
    //  1    1    0     1
    //  1    1    1    hi-Z
    genvar j;
    for (j = 0; j < 32; j = j + 1)
    begin
        assign gpio_data_oe[j] = out[j] && (!latch_data[j] || !od[j]);
    end
    assign gpio_data_out = latch_data;
    
    // Interrupt generation
    integer i;
    reg [31:0] last_read_port_data;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            last_read_port_data <= 32'b0;
            int_status <= 32'b0;
        end
        else if (int_clear_request != 32'b0)
            int_status <= int_status & ~int_clear_request;
        else
        begin
            last_read_port_data <= read_port_data;
            for (i = 0; i < 32; i = i + 1)
            begin
                if (int_enable[i])
                begin
                    if (int_edge_mode[i])
                    begin
                        if (int_positive[i] && read_port_data[i] && !last_read_port_data[i])
                            int_status[i] <= 1'b1;
                        if (int_negative[i] && !read_port_data[i] && last_read_port_data[i])
                            int_status[i] <= 1'b1;
                    end
                    else
                    begin
                        if (int_positive[i] && read_port_data[i])
                            int_status[i] <= 1'b1;
                        if (int_negative[i] && !read_port_data[i])
                            int_status[i] <= 1'b1;
                    end
                end
            end
        end
    end
    assign intr = int_status != 32'b0;
    
endmodule
