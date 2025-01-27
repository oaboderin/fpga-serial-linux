module receiver (
    input wire clk,
    input wire reset,
	input wire brgen,
    input wire enable,
    input wire [1:0] size,
    input wire stop2,               // Stop bit setting (1 or 2 stop bits)
    input wire [1:0] parity,        // Parity settings (0=None, 1=Even, 2=Odd)
    output reg fe,                   // Framing error flag
	output reg pe,
	input wire clear_fe,
	input wire clear_pe,
    output reg [8:0] data,           // Received data
    output reg data_request,         // Indicates data is ready
    input wire in                   // UART input signal
);

	reg [2:0]state;
    parameter IDLE = 3'b000;
    parameter START = 3'b001;
    parameter DATA = 3'b010;
    parameter PARITY = 3'b011;
    parameter STOP = 3'b100;

    logic [2:0] bit_count;             // Tracks bit index for data reception
    reg [7:0] shift_reg;           // Shift register for received data
    reg parity_bit, received_parity;

    reg [2:0] start_samples;       // Holds sampled bits for majority voting
	
	logic [1:0] stop_bit_count;       // Counter for stop bits
	
	logic [2:0] data_length; // 5–8 bits
	assign data_length = size + 3'd4;
	
	reg [3:0] counter;              // Counter for baud rate ticks (1/16)
    reg brgen_old;                 // Previous value of brgen
    
	
	always_ff @(posedge clk) begin
    if (reset == 1'b0) begin
        brgen_old <= 0;
        counter <= 0;
		state <= IDLE;
        bit_count <= 0;
        data_request <= 0;
        start_samples <= 3'b000;
    end else begin 
	if(enable) begin
        brgen_old <= brgen;
        if (brgen && !brgen_old) begin
            counter <= counter + 1;
			
			case (state)
				IDLE: begin
					if (counter == 4'd15) 
					begin 
						counter <= 0;
					end
					data_request <= 0;
					fe <= 0;
					start_samples <= 3'b000;
					if (!in && enable) state <= START; // Detect possible start bit
				end
				START: begin
					if (counter == 3'd6) start_samples[0] <= in; // 7th sample
					if (counter == 3'd7) start_samples[1] <= in; // 8th sample
					if (counter == 4'd8) start_samples[2] <= in; // 9th sample
					if (counter == 4'd15) begin
					counter <= 0;
					// Majority voting
					if ((start_samples[0] + start_samples[1] + start_samples[2]) <= 1) begin
						state <= DATA;
						stop_bit_count <= stop2;
						bit_count <= 0;
					end else
						state <= IDLE;
					end
				end
				DATA: 
					if (counter == 4'd15) begin
					counter <= 0;
					shift_reg[bit_count] <= in;
                    bit_count <= bit_count + 1;
                    if (bit_count == (data_length)) begin 
						state <= (parity != 2'b00) ? PARITY : STOP;
					end else begin
						state <= DATA;
					end
				end
				PARITY: 
					if (counter == 4'd15) begin
					counter <= 0;
					received_parity <= in;
                    if ((parity == 2'b01 && received_parity != parity_bit) || // Odd parity error
                        (parity == 2'b10 && received_parity != parity_bit))   // Even parity error
                        begin 
							pe <= 1;
						end
                    state <= STOP;
                    end
				STOP: 
					if (counter == 4'd15) begin
					counter <= 0;
					if (stop_bit_count >= 1) begin
						if(in != 1'b1) fe <= 1; 
						else begin
						state <= STOP;
						end
					end else begin
						if(in != 1'b1) fe <= 1; 
						else begin
						state <= IDLE;
						data_request <= 1;
						data <= shift_reg;
						end
						end
				end
				default: state <= IDLE; // Reset to IDLE for safety

				endcase
           
        end
		end
    end
	end
	
	always_ff @ (posedge clk) begin
		if (reset == 1'b0) begin
			fe <= 0;
			pe <= 0;
		end else begin
			if(clear_fe)
				fe <= 0;
			if(clear_pe)
				pe <= 0;
		end 
	end
	
	always_comb begin
    case (size)
        2'b00: parity_bit = ^shift_reg[4:0];
        2'b01: parity_bit = ^shift_reg[5:0];
        2'b10: parity_bit = ^shift_reg[6:0];
        2'b11: parity_bit = ^shift_reg[7:0];
        default: parity_bit = 1'b0;
    endcase
end
	
endmodule