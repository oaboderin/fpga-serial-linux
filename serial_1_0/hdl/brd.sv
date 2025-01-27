module brd (
    input wire clk,
	input wire reset,
    input wire enable,
    input wire [23:0] ibrd,
    input wire [7:0] fbrd,
    output reg out
);
    

    // Initialize counters
    reg [31:0] count;
    reg [31:0] fr_count;


    always_ff @(posedge clk) begin
		if (reset == 1'b0) begin
			out <= 0;
			count <= 0;
			fr_count <= 0;
		end else if (enable) begin
			fr_count <= fr_count + fbrd;
			if (fr_count >= 9'd256) begin
				fr_count <= fr_count - 9'd256; 
				count <= count + 1;
			end
			if (count >= ibrd) begin
				count <= 0;
				out <= ~out;
			end else begin
				count <= count + 1;
			end
		end
	end

endmodule