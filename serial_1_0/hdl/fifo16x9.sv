module fifo16x9 (
    input wire clk,                   
    input wire reset,                 
    input wire [8:0] wr_data,       
    input wire wr_request,            
    output reg [8:0] rd_data,        
    input wire rd_request,            
    output wire empty,              
    output wire full,                 
    output reg overflow,       
    input wire clear_overflow_request,
    output reg [4:0] wr_index,       
    output reg [4:0] rd_index,      
    output reg [4:0] watermark       
);		
	
	parameter DEPTH = 5'd16;              
    reg [8:0] fifo [0:15];            

    // Write logic
    always_ff @(posedge clk) begin
        if (reset == 1'b0) begin
            wr_index <= 0;
            overflow <= 0;
        end else begin
            if (clear_overflow_request)
                overflow <= 0;
            if (wr_request && !full) begin
                fifo[wr_index[3:0]] <= wr_data;  // Write to FIFO
                wr_index <= wr_index + 1;       // Increment write index
            end else if (wr_request && full) begin
                overflow <= 1;                  // Set overflow flag if FIFO is full
            end
        end
    end

    // Read logic
	always_comb 
	begin
		if (!empty)
		begin
			rd_data = fifo[rd_index[3:0]];  
		end
		else
			rd_data = 9'b0;                 
	end
	
	// Read request handling
    always_ff @(posedge clk) 
    begin
        if (reset == 1'b0) 
        begin
            rd_index <= 0;
        end else if (rd_request && !empty) 
		begin
            rd_index <= rd_index + 1;           
        end
    end

    // Status signals
    assign empty = (wr_index == rd_index);           // FIFO is empty
    assign full = (wr_index[3:0] == rd_index[3:0]) && (wr_index[4] != rd_index[4]);   // FIFO is full 
    //assign watermark = {full,(wr_index[3:0] - rd_index[3:0] + DEPTH) % DEPTH};
	//assign watermark = full ? DEPTH: (wr_index[3:0] - rd_index[3:0] + DEPTH) % DEPTH;
	assign watermark = full ? DEPTH : ((wr_index >= rd_index) ? (wr_index - rd_index) : (DEPTH + wr_index - rd_index));
    //assign watermark = 5'b10101;
    

endmodule
