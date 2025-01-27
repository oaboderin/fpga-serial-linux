module transmitter (
    input wire clk,              // System clock
	input wire reset,
    input wire brgen,            // Baud rate generator output
    input wire enable,           // Enable signal for transmission
    input wire [1:0] size,       // Data size (5 to 8 bits)
    input wire stop2,            // Stop bit control (1 or 2 stop bits)
    input wire [1:0] parity,     // Parity control (00 - None, 01 - Even, 10 - Odd)
    input wire fifo_empty,       // FIFO empty flag
    input wire [8:0] data,       // Data to be transmitted
    output reg data_request,     // Read request for FIFO
    output reg out               // Serial data output
);

    // FSM states
	reg [2:0]state;
    parameter IDLE       = 3'b000;
    parameter START_BIT  = 3'b001;
    parameter DATA_BITS  = 3'b010;
    parameter PARITY_BIT = 3'b011;
    parameter STOP_BIT   = 3'b100;

    logic [3:0] bit_count;            // Counter for data bits
    reg [7:0] shift_reg;            // Shift register for data bits
    reg parity_bit;                 // Calculated parity bit
	reg [1:0] stop_bit;
    logic [1:0] stop_bit_count;       // Counter for stop bits

    reg [3:0] counter;              // Counter for baud rate ticks (1/16)
    reg brgen_old;                 // Previous value of brgen

	always_ff @ (posedge(clk))
    begin
        if ((reset == 1'b0) || !enable)
        begin
            counter <= 0;
            state <= IDLE;
			data_request <= 1'b0;
			out <= 1'b1; // Idle state for serial line (high)
        end else begin
		if(enable) begin
			brgen_old <= brgen;
			if (brgen && !brgen_old) begin
				counter <= counter + 1;
				
			case (state)
				IDLE: begin
					out <= 1'b1; 
					counter <= 0;
					if (!fifo_empty)
					begin
						state <= START_BIT;
					end
				end

				START_BIT: begin
					out <= 1'b0;  // Start bit
					shift_reg <= data;
					if (counter == 4'd15) begin
						state <= DATA_BITS;
						bit_count <= 0;
						counter <= 0;
					end else state <= START_BIT;
				end

				DATA_BITS: 
					if (counter == 4'd15) begin
					counter <= 0;
					out <= shift_reg[bit_count];
					bit_count <= bit_count + 1;
					if (bit_count == size + 5) begin // Adjust for size (00 for 5- 0b11 for 8 bits)
						state <= (parity == 2'b00) ? STOP_BIT : PARITY_BIT;
					end else begin
						state <= DATA_BITS;
						end
				end

				PARITY_BIT: 
				if (counter == 4'd15) begin
					counter <= 0;
					out <= parity_bit;
					state <= STOP_BIT;
					stop_bit_count <= stop_bit;
				end

				STOP_BIT: 
				if (counter == 4'd15) begin
					counter <= 0;
					out <= 1'b1;  // Stop bit(s) high
					stop_bit_count <= stop_bit_count - 1;
					if (stop_bit_count == 0) begin
						if (!fifo_empty) begin
							state <= START_BIT;  // Go to START_BIT if FIFO is not empty
						end else begin
							state <= IDLE;       // Go to IDLE if FIFO is empty
						end
					end else state <= STOP_BIT;
				end
				default: state <= IDLE; // Reset to IDLE for safety
			endcase	
			end

		end 
		end
	end
	
    // Calculate parity based on data and parity type
    always_comb begin
        case (parity)
            2'b01: parity_bit = ^data;         // Even parity
            2'b10: parity_bit = ~^data;        // Odd parity
            default: parity_bit = 1'b0;        // No parity
        endcase
    end
	
	always_comb begin
        case (stop2)
            1'b0: stop_bit = 2'b01;         
            1'b1: stop_bit = 2'b10;        
            default: stop_bit = 2'b01;        
        endcase
    end

	// Control data_request based on FSM state
	always_comb begin
		data_request = (state == START_BIT); // Only request new data when entering START_BIT state
	end

endmodule

