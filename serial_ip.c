#include <stdint.h>
#include <stdio.h>
#include <stdlib.h> 
#include <stdbool.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include "../address_map.h"

#define CLK_FREQ 100000000 
#define SPAN_IN_BYTES 32
#define SERIAL_BASE_OFFSET 0x20000
#define DATA_REG_OFFSET    0
#define STATUS_REG_OFFSET  1
#define CONTROL_REG_OFFSET 2
#define BRD_REG_OFFSET     3

// Status register bit masks
#define FIFO_EMPTY_MASK    (1 << 0)
#define FIFO_FULL_MASK     (1 << 2)
#define FIFO_OVERFLOW_MASK (1 << 4)

// Control register bit masks
#define ENABLE_MASK (1 << 4)
#define TEST_MASK 	(1 << 5)
#define DATA_LENGTH_MASK   0x03  
#define PARITY_MODE_MASK   0x0C  
#define STOP_BITS_MASK     0x100  

// BRD register bit masks
#define IBRD_OFFSET		8
#define FBRD_MASK 		0xFF  

uint32_t *base = NULL; 

void printBinary(uint32_t num);
bool serialOpen(void);
void printUsage(void);
void printFifoStatus(uint32_t status);
uint32_t readData(void);
void writeData(uint32_t value);
uint32_t readStatus(void);
uint32_t readBaudRate(void);
void setBaudRate(float baudRate);
void enableBRD(void);
void disableBRD(void);
void enableTest(void);
void disableTest(void);
void clear_OV(void);
void setDataLength(uint8_t dl);
void setParityMode(uint8_t mode);
void setStopBits(uint8_t bits);


int main(int argc, char* argv[])
{
	uint32_t data, status;
	float baudrate;
	if (argc >= 2 && (strcmp(argv[1], "read") == 0 || strcmp(argv[1], "r") == 0)) {
        // Read operation
		serialOpen();
        int num_reads = 1; //default number of reads
        if (argc > 2) {
            num_reads = atoi(argv[2]);
            if (num_reads <= 0){
				//verify valid number of reads
				num_reads = 1; 
			}
        }

        for (int i = 0; i < num_reads; i++) {
            status = readStatus();
            if (!(status & FIFO_EMPTY_MASK)) {
                data = readData();
                printf("Read data[%d]: %d\n", i, data);
            } else {
                printf("FIFO is empty\n");
                break;
            }
        }
		
    }else if (argc >= 3 && (strcmp(argv[1], "write") == 0 || strcmp(argv[1], "w") == 0)) {
        // Write operation
		serialOpen();
        // Process each value provided
        for (int i = 2; i < argc; i++) {
            status = readStatus();
            if (!(status & FIFO_FULL_MASK)) {
                data = (uint32_t)strtoul(argv[i], NULL, 0);
				writeData(data);
                printf("Successfully wrote %d\n", data);
                
            } else {
				data = (uint32_t)strtoul(argv[i], NULL, 0);
				//writeData(data);
                //printf("Wrote %d. FIFO is now full\n", data);
				printf("FIFO is now full\n");
                break;
            }
        }
    }
    else if (strcmp(argv[1], "status") == 0 || strcmp(argv[1], "s") == 0) {
        // Status 
		serialOpen();
        status = readStatus();
        printFifoStatus(status);
    }
	else if (strcmp(argv[1], "clear") == 0 || strcmp(argv[1], "co") == 0) {
        // Status 
		serialOpen();
		clear_OV();
    }
	else if (argc == 3 && (strcmp(argv[1], "baudrate") == 0 || strcmp(argv[1], "b") == 0)){
		// Set baud rate
		serialOpen();
		baudrate = strtof(argv[2], NULL);
		if (baudrate <= 0){
			printf("Invalid baud rate entered.");
		}else {
			setBaudRate(baudrate);
		}
	}
	else if (argc == 2 && (strcmp(argv[1], "baudrate") == 0 || strcmp(argv[1], "b") == 0)){
		// Set baud rate
		serialOpen();
		printf("Baud rate is ");
		printBinary(readBaudRate());
	}
	else if (strcmp(argv[1], "enable") == 0){
		// enable brd
		serialOpen();
		enableBRD();
	}
	else if (strcmp(argv[1], "disable") == 0){
		// disable brd
		serialOpen();
		disableBRD();
	}
	else if (strcmp(argv[1], "test") == 0){
		// turn on/off test
		if(argc > 2 && strcmp(argv[2], "off") == 0){
			serialOpen();
			disableTest();
		}else{
			serialOpen();
			enableTest();
		}
	}
	else if (strcmp(argv[1], "setup") == 0){
		// settings for transmission
		
		serialOpen();
	}
	else if (strcmp(argv[1], "dl") == 0){
		// settings for transmission
		if(argc > 2){
			uint8_t dl = atoi(argv[2]);
            if (dl >= 5 || dl <= 8){
				serialOpen();
				setDataLength(dl);
				
			}else {
				printf("usage: sudo ./serial dl DATA_LENGTH(5 TO 8)");
			}
			
		}else{
			printf("usage: sudo ./serial dl DATA_LENGTH(5 TO 8)");
		}
	}
	else if (strcmp(argv[1], "p") == 0){
		// settings for transmission
		if(argc > 2){
			uint8_t mode = atoi(argv[2]);
            if (mode >= 0 || mode <= 2){
				serialOpen();
				setParityMode(mode);
				
			}else{
				printf("usage: sudo ./serial p [0,1,2]");
			}
			
		}else{
			printf("usage: sudo ./serial p [0,1,2]");
		}
	}
	else if (strcmp(argv[1], "stop") == 0){
		// settings for transmission
		if(argc > 2){
			uint8_t stop = atoi(argv[2]);
            if (stop == 1 || stop == 2){
				serialOpen();
				setStopBits(stop);
				
			}else{
				printf("usage: sudo ./serial stop [1,2]");
			}
			
		}else{
			printf("usage: sudo ./serial stop [1,2]");
		}
	}
	else if(strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "--h") == 0){
		printUsage();
		//return 1;
	}
    else {
        printf("Invalid command\n");
        printUsage();
        //return 1;
    }

return EXIT_SUCCESS;
}

bool serialOpen()
{
	int file = open("/dev/mem", O_RDWR | O_SYNC);
	bool bOK = (file >= 0);
	if(bOK){
		base = mmap(NULL, SPAN_IN_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED,
			file, AXI4_LITE_BASE + SERIAL_BASE_OFFSET);
		bOK = (base != MAP_FAILED);


		//Close /dev/mem
		close(file);
	}
return bOK;

}

void printFifoStatus(uint32_t status) {
    printf("FIFO Status: ");
	printBinary(status);
    printf("Empty: %s\n", (status & FIFO_EMPTY_MASK) ? "Yes" : "No");
    printf("Full: %s\n", (status & FIFO_FULL_MASK) ? "Yes" : "No");
    printf("Overflow: %s\n", (status & FIFO_OVERFLOW_MASK) ? "Yes" : "No");
}

uint32_t readData() {
	uint32_t value = *(base + DATA_REG_OFFSET);
    return value;
}

void writeData(uint32_t value) {
    *(base + DATA_REG_OFFSET) = value;
}

uint32_t readStatus(void) {
	uint32_t value = *(base + STATUS_REG_OFFSET);
    return value;
}

void setBaudRate(float baudRate) {
    float divisor = (float)(CLK_FREQ / (32 * baudRate));

    uint32_t ibrd = (uint32_t)divisor;                    
    uint8_t fbrd = (uint8_t)((divisor - ibrd) * 256);   

    //printf("Baud rate: %d (ibrd = %d, fbrd = %d)\n", baudRate, ibrd, fbrd);
	printf("BRD Register: ");
	printBinary((ibrd << IBRD_OFFSET) | (fbrd & FBRD_MASK));
    *(base + BRD_REG_OFFSET) = (ibrd << IBRD_OFFSET) | (fbrd & FBRD_MASK);
}

uint32_t readBaudRate(void) {
	uint32_t value = *(base + BRD_REG_OFFSET);
    return value;
}

void enableBRD(void){
	*(base + CONTROL_REG_OFFSET)|= ENABLE_MASK;
}

void disableBRD(void){
	*(base + CONTROL_REG_OFFSET) &= ~ENABLE_MASK;
}

void enableTest(void){
	*(base + CONTROL_REG_OFFSET)|= TEST_MASK;
}

void disableTest(void){
	*(base + CONTROL_REG_OFFSET) &= ~TEST_MASK;
}

void clear_OV(void){
	*(base + STATUS_REG_OFFSET) = 0x01;
}

void setDataLength(uint8_t dl){
	
    uint32_t control = *(base + CONTROL_REG_OFFSET);
    control &= ~DATA_LENGTH_MASK;           // Clear current data length bits
    control |= (dl - 5);                    // Set new data length (5 to 8 bits)
    *(base + CONTROL_REG_OFFSET) = control;
}


void setParityMode(uint8_t mode){
	uint32_t control = *(base + CONTROL_REG_OFFSET);
    control &= ~PARITY_MODE_MASK;            // Clear current parity bits
    control |= (mode << 2);                  // Set new parity mode bits
    *(base + CONTROL_REG_OFFSET) = control;
}

void setStopBits(uint8_t bits){
	uint32_t control = *(base + CONTROL_REG_OFFSET);
    control &= ~STOP_BITS_MASK;              // Clear current stop bits setting
    if (bits == 2) {
        control |= STOP_BITS_MASK;           // Set stop bits to 2
    }
    *(base + CONTROL_REG_OFFSET) = control;
}

void printUsage() {
    printf("Usage:\n");
    printf("  Read:\n");
    printf("    ./serial read optional: num_reads\n");
    printf("   	./serial r optional: num_reads\n");
    printf("  Write:\n");
    printf("    ./serial write value1 optional: value2 value3 ...\n");
    printf("   	./serial w value1 optional: value2 [value3 ...\n");
	printf("  Set baud rate:\n");
    printf("    ./serial baudrate value\n");
    printf("   	./serial b value\n");
    printf("  Check status:\n");
    printf("    ./serial status\n");
    printf("    ./serial s\n");
    printf("\nNotes:\n");
    printf("- Values can be in decimal or hex (prefix with 0x)\n");
    printf("- Multiple writes can be specified in a single command\n");
    printf("- Optional num_reads parameter specifies how many reads to perform\n");
}

void printBinary(uint32_t num) {
    for (int i = 31; i >= 0; i--) {
        printf("%d", (num >> i) & 1);
        if (i % 8 == 0 && i != 0) printf(" "); 
    }
    printf("\n");
}


