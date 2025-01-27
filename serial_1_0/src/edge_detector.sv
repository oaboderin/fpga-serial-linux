module edge_detector (
	input wire clk,
	input wire reset,
	input wire signal_in,
	output reg signal_out
);
	reg signal_ff;
	
	always_ff @(posedge clk)
	begin
		if(reset == 1'b0)
		begin
			signal_ff <= 1'b0;
			signal_out <= 1'b0;
		end else begin
			signal_ff <= signal_in;
			signal_out <= signal_in && !signal_ff;
			end
	end
endmodule