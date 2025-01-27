// Serial IP 
// Serial Driver (serial_driver.c)


//-----------------------------------------------------------------------------
// Hardware Target
//-----------------------------------------------------------------------------

// Target Platform: Xilinx XUP Blackboard

// Hardware configuration:
// 
// AXI4-Lite interface
//   Mapped to offset of 0x20000


// Load kernel module with insmod serial_driver.ko [param=___]

//-----------------------------------------------------------------------------
#include <linux/kernel.h>     // kstrtouint
#include <linux/module.h>     // MODULE_ macros
#include <linux/init.h>       // __init
#include <linux/kobject.h>    // kobject, kobject_atribute,
                              // kobject_create_and_add, kobject_put
#include <asm/io.h>           // iowrite, ioread, ioremap_nocache (platform specific)
#include <linux/types.h>
#include "../address_map.h"   // overall memory map
#include "serial_regs.h"          // register offsets in QE IP


// Kernel module information
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Olajumoke Aboderin");
MODULE_DESCRIPTION("Serial IP Driver");


// Global variables
static unsigned int *base = NULL;

// Subroutines
void write_register(uint32_t offset, uint32_t value) {
    iowrite32(value, base + offset);
}

uint32_t read_register(uint32_t offset) {
    return ioread32(base + offset);
}

// kernel objects
static ssize_t baud_rate_show(struct kobject *kobj, struct kobj_attribute *attr, char *buffer) {
    uint32_t brd = read_register(BRD_REG_OFFSET);
    uint32_t ibrd = brd >> 8;
    uint32_t fbrd = brd & 0xFF;
    float baud_rate = (float)CLK_FREQ / (16 * (ibrd + (fbrd / 256.0)));
    return sprintf(buffer, "%.2f\n", baud_rate);
}

static ssize_t baud_rate_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count) {
    float baud_rate;
    sscanf(buffer, "%f", &baud_rate);

    uint32_t divisor = CLK_FREQ / (16 * baud_rate);
    uint32_t ibrd = divisor / 1;
    uint32_t fbrd = (uint32_t)((divisor - ibrd) * 256);
	
	uint32_t control = read_register(CONTROL_REG_OFFSET);
    write_register(BRD_REG_OFFSET, (ibrd << 8) | (fbrd & 0xFF));
	write_register(CONTROL_REG_OFFSET, (control | ENABLE_MASK));
	write_register(CONTROL_REG_OFFSET, (control | TEST_MASK));
    return count;
}

static ssize_t word_size_show(struct kobject *kobj, struct kobj_attribute *attr, char *buffer) {
    uint32_t control = read_register(CONTROL_REG_OFFSET);
    return sprintf(buffer, "%d\n", (control & DATA_LENGTH_MASK) + 5);
}

static ssize_t word_size_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count) {
    int size;
    sscanf(buffer, "%d", &size);

    uint32_t control = read_register(CONTROL_REG_OFFSET);
    control &= ~DATA_LENGTH_MASK; // Clear current setting
    control |= (size - 5);                // Set new size
    write_register(CONTROL_REG_OFFSET, control);

    return count;
}

static ssize_t parity_mode_show(struct kobject *kobj, struct kobj_attribute *attr, char *buffer) {
    uint32_t control = read_register(CONTROL_REG_OFFSET);
    return sprintf(buffer, "%d\n", (control & PARITY_MODE_MASK) >> 2);
}

static ssize_t parity_mode_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count) {
    int mode;
    sscanf(buffer, "%d", &mode);

    uint32_t control = read_register(CONTROL_REG_OFFSET);
    control &= ~PARITY_MODE_MASK; // Clear current setting
    control |= (mode << 2);               // Set new mode
    write_register(CONTROL_REG_OFFSET, control);

    return count;
}

// Sysfs attributes for tx_data and rx_data
static ssize_t tx_data_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count) {
    uint32_t data;
    sscanf(buffer, "%d", &data);

    write_register(DATA_REG_OFFSET, data);
    return count;
}

static ssize_t rx_data_show(struct kobject *kobj, struct kobj_attribute *attr, char *buffer) {
    uint32_t status = read_register(STATUS_REG_OFFSET);
    if (status & 1) { // Check RX FIFO empty
        return sprintf(buffer, "-1\n"); // FIFO is empty
    }
    uint32_t data = read_register(DATA_REG_OFFSET);
    return sprintf(buffer, "%d\n", data);
}

// Attribute Definitions
static struct kobj_attribute baud_rate_attr = __ATTR(baud_rate, 0664, baud_rate_show, baud_rate_store);
static struct kobj_attribute word_size_attr = __ATTR(word_size, 0664, word_size_show, word_size_store);
static struct kobj_attribute parity_mode_attr = __ATTR(parity_mode, 0664, parity_mode_show, parity_mode_store);
static struct kobj_attribute tx_data_attr = __ATTR(tx_data, 0220, NULL, tx_data_store);
static struct kobj_attribute rx_data_attr = __ATTR(rx_data, 0444, rx_data_show, NULL);

static struct attribute *attrs[] = {
    &baud_rate_attr.attr,
    &word_size_attr.attr,
    &parity_mode_attr.attr,
    &tx_data_attr.attr,
    &rx_data_attr.attr,
    NULL
};

static struct attribute_group attr_group = {
    .attrs = attrs
};

static struct kobject *kobj;

// Module Init/Exit
static int __init initialize_module(void) {
    int result;

	printk(KERN_INFO "Serial driver: starting\n");
	
    // Create serial directory under /sys/kernel
    kobj = kobject_create_and_add("serial", NULL);
    if (!kobj) {
        printk(KERN_ALERT "Serial driver: failed to create and add kobj\n");
        return -ENOENT;
    }

    result = sysfs_create_group(kobj, &attr_group);
    if (result !=0) 
        return result;
	
	 // Physical to virtual memory map to access gpio registers
    base = (unsigned int*)ioremap(AXI4_LITE_BASE + SERIAL_BASE_OFFSET,
                                          SPAN_IN_BYTES);
    if (base == NULL)
        return -ENODEV;

    printk(KERN_INFO "Serial driver: initialized\n");

    return 0;
}

static void __exit exit_module(void) {
    kobject_put(kobj);
    printk(KERN_INFO "Serial Driver: exit\n");
}

module_init(initialize_module);
module_exit(exit_module);

