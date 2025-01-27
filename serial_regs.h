// Serial IP Library Registers
// Olajumoke Aboderin

//-----------------------------------------------------------------------------
// Hardware Target
//-----------------------------------------------------------------------------

// Target Platform: Xilinx XUP Blackboard

// Hardware configuration:
// 
// AXI4-Lite interface:
//  Mapped to offset of 0x20000
// 


//-----------------------------------------------------------------------------
// Device includes, defines, and assembler directives
//-----------------------------------------------------------------------------

#ifndef QE_REGS_H_
#define QE_REGS_H_

#define CLK_FREQ 100000000 
#define SPAN_IN_BYTES 32
#define SERIAL_BASE_OFFSET 0x20000
#define DATA_REG_OFFSET    0
#define STATUS_REG_OFFSET  1
#define CONTROL_REG_OFFSET 2
#define BRD_REG_OFFSET     3

// Status register bit masks
#define RXFE (1 << 1)
#define TXFE (1 << 4)

// Control register bit masks
#define ENABLE_MASK (1 << 4)
#define TEST_MASK 	(1 << 5)
#define DATA_LENGTH_MASK   0x03  
#define PARITY_MODE_MASK   0x0C  
#define STOP_BITS_MASK     0x100  

// BRD register bit masks
#define IBRD_OFFSET		8
#define FBRD_MASK 		0xFF  

#endif
