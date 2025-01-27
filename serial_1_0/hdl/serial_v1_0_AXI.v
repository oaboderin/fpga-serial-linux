// AXI4-lite GPIO IP implementation
// (serial_v1_0_AXI.v)
// Jason Losh, Olajumoke Aboderin based on Xilinx IP tool auto-generated file
//
// Contains:
// AXI4-lite interface
// Serial memory-mapped interface
// Serial port interface and implemention

`timescale 1 ns / 1 ps

    module serial_v1_0_AXI #
    (
        // Bit width of S_AXI address bus
        parameter integer C_S_AXI_ADDR_WIDTH = 4
    )
    (
        // Ports to top level module (what makes this the GPIO IP module)
		output wire CLK_OUT,
		output wire tx_out,
		input wire rx_in,
		
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

    // Internals
    reg [31:0] status; 
    reg [31:0] control;
    reg [31:0] brd;
	
	
	// Transmitter
	 reg [8:0] tx_latch_data;
	 reg tx_fifo_wr_request, tx_fifo_rd_request;
	 reg tx_wr_request, tx_rd_request;
	 reg [8:0] tx_fifo_data_in;
	 wire tx_fifo_empty, tx_fifo_full, tx_fifo_overflow;
	 reg tx_clear_overflow;
	 wire [4:0] tx_wr_index, tx_rd_index, tx_watermark;
	
	// Receiver
	reg [8:0] rx_latch_data;
	 reg rx_fifo_wr_request, rx_fifo_rd_request;
	 reg rx_wr_request, rx_rd_request;
	 reg [8:0] rx_data_out;
	 wire rx_fifo_empty, rx_fifo_full, rx_fifo_overflow;
	 reg rx_clear_overflow, clear_pe, clear_fe;
	 wire [4:0]rx_wr_index, rx_rd_index, rx_watermark;
	 wire rx_fe,rx_pe;
	
	// Status Register w1c
	reg [31:0] status_w1c;
	assign status_w1c = {24'b0, clear_pe, clear_fe, tx_clear_overflow, 2'b0, rx_clear_overflow, 2'b0};
	
	// Baud Rate Register
	wire [23:0]ibrd;
	wire [7:0]fbrd;
	wire brd_out;
	assign ibrd = brd[31:8];
	assign fbrd = brd[7:0];
    
    // Register map
    // ofs  fn
    //   0  data (r/w)
    //   4  status (r/w1c)
    //   8  control (r/w)
    //  12  brd (r/w)
    
    // Register numbers
    localparam integer DATA_REG		= 3'b000;
    localparam integer STATUS_REG	= 3'b001;
    localparam integer CONTROL_REG	= 3'b010;
    localparam integer BRD_REG		= 3'b011;
    
    
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

	// FIFO instantation 
	fifo16x9 tx_fifo(
		.clk(axi_clk),                  
		.reset(axi_resetn),                 
		.wr_data(tx_latch_data),        
		.wr_request(tx_fifo_wr_request), 
		.rd_data(tx_fifo_data_in),    
		.rd_request(tx_fifo_rd_request),     
		.empty(tx_fifo_empty),           
		.full(tx_fifo_full),           
		.overflow(tx_fifo_overflow),     
		.clear_overflow_request(tx_clear_overflow),
		.wr_index(tx_wr_index),       
		.rd_index(tx_rd_index),      
		.watermark(tx_watermark) 
	);
	
	fifo16x9 rx_fifo(
		.clk(axi_clk),                  
		.reset(axi_resetn),                 
		.wr_data(rx_data_out),        
		.wr_request(rx_fifo_wr_request), 
		.rd_data(rx_latch_data),    
		.rd_request(rx_fifo_rd_request),     
		.empty(rx_fifo_empty),           
		.full(rx_fifo_full),           
		.overflow(rx_fifo_overflow),     
		.clear_overflow_request(rx_clear_overflow),
		.wr_index(rx_wr_index),       
		.rd_index(rx_rd_index),      
		.watermark(rx_watermark) 
	);
	
	// Edge detectors instantation
	edge_detector tx_wr_edge_det(
		.clk(axi_clk),
		.reset(axi_resetn),
		.signal_in(tx_wr_request),
		.signal_out(tx_fifo_wr_request)
	);
	
	edge_detector tx_rd_edge_det(
		.clk(axi_clk),
		.reset(axi_resetn),
		.signal_in(tx_rd_request),
		.signal_out(tx_fifo_rd_request)
	);
	
	edge_detector rx_wr_edge_det(
		.clk(axi_clk),
		.reset(axi_resetn),
		.signal_in(rx_wr_request),
		.signal_out(rx_fifo_wr_request)
	);
	
	edge_detector rx_rd_edge_det(
		.clk(axi_clk),
		.reset(axi_resetn),
		.signal_in(rx_rd_request),
		.signal_out(rx_fifo_rd_request)
	);
	
	// Baud Rate Generator instantation
	brd serial_brd (
		.clk(axi_clk),
		.enable(control[4]),
		.ibrd(ibrd),
		.fbrd(fbrd),
		.out(brd_out)
);
    assign status = {11'b0, tx_watermark, 3'b0, rx_watermark, 
					rx_pe, rx_fe, tx_fifo_overflow, tx_fifo_empty, 
					tx_fifo_full,rx_fifo_overflow,rx_fifo_empty,rx_fifo_full};
	assign CLK_OUT = brd_out & control[5];
	assign intr = (control[6] & ~status[1]) | (control[7] & status[4]);  // INT_ON_RX and RXFE clear
                    // INT_ON_TX and TXFE set

	assign control[31:9] = 13'b0;
	
	// Transmitter instantation
	transmitter tx_serializer(
		.clk(axi_clk),  
		.reset(axi_resetn),
		.brgen(brd_out),            
		.enable(control[4]),           
		.size(control[1:0]),       
		.stop2(control[8]),            
		.parity(control[3:2]),    
		.fifo_empty(tx_fifo_empty),      
		.data(tx_fifo_data_in),     
		.data_request(tx_rd_request),    
		.out(tx_out)          
	);

	// Receiver instantation
	receiver rx_deserializer(
		.clk(axi_clk),
		.reset(axi_resetn),
		.brgen(brd_out),
		.enable(control[4]),
		.size(control[1:0]),
		.stop2(control[8]),              
		.parity(control[3:2]),        
		.fe(rx_fe),
		.pe(rx_pe),
		.clear_fe(clear_fe),
		.clear_pe(clear_pe),
		.data(rx_data_out),          
		.data_request(rx_wr_request),         
		.in(rx_in) 
	);
	
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
            tx_latch_data <= 9'b0;
            status <= 32'b0;
            control <= 32'b0;
            brd <= 32'b0;
        end 
        else 
        begin
            if (wr)
            begin
                case (axi_awaddr[3:2])
                    DATA_REG:
							begin
								tx_latch_data <= S_AXI_WDATA[8:0];
								tx_wr_request <= 1'b1;
							end
                    STATUS_REG:
                        for (byte_index = 0; byte_index <= 2; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
								status_w1c[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
								
                    CONTROL_REG: 
                        for (byte_index = 0; byte_index <= 2; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
                                control[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    BRD_REG:
                        for (byte_index = 0; byte_index <= 2; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
                                brd[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    
                endcase
            end
            else begin
                //int_clear_request <= 32'b0;
				tx_wr_request <= 1'b0;
				status_w1c <= 32'b0;
				end
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
		case (raddr[3:2])
		    DATA_REG: 
				begin
					axi_rdata <= {23'b0, rx_latch_data};
					rx_rd_request <= 1'b1;
				end
		    STATUS_REG:
				begin
					axi_rdata <= status;	
				end
		    CONTROL_REG: 
		        axi_rdata <= control;
		    BRD_REG: 
			     axi_rdata <= brd;
		endcase
            end 
              else begin
				rx_rd_request <= 1'b0;
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
	
endmodule



