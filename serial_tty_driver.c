#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/interrupt.h>
#include <linux/init.h>
#include <linux/slab.h>
#include <linux/irq.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_device.h>
#include <linux/of_irq.h>
#include <linux/types.h>
#include <linux/tty.h>
#include <linux/tty_flip.h>
#include <linux/io.h>
#include <asm/io.h>
#include "../address_map.h"
#include "serial_regs.h"

#define DEVICE_NAME "ttyserial"
#define TTY_BUFFER_SIZE 1024

// Status register masks
#define STATUS_RX_EMPTY_MASK (1 << 1)
#define STATUS_TX_FULL_MASK (1 << 4)




// Globals
static uint32_t *base = NULL;
static struct tty_driver *serial_tty_driver;
static struct tty_port serial_tty_port;



MODULE_LICENSE("GPL");
MODULE_AUTHOR("Olajumoke Aboderin");
MODULE_DESCRIPTION("Serial TTY Driver");


// Interrupt handler
static irqreturn_t serial_irq_handler(int irq, void *dev_id) {
    struct tty_struct *tty = tty_port_tty_get(&serial_tty_port);
    if (!tty)
        return IRQ_NONE;

    uint32_t status = ioread32(base + STATUS_REG_OFFSET);

    // Handle RX data
    while (!(status & STATUS_RX_EMPTY_MASK)) {
        char ch = (char)ioread32(base + (DATA_REG_OFFSET));
        tty_insert_flip_char(&serial_tty_port, ch, TTY_NORMAL);
        status = ioread32(base + (STATUS_REG_OFFSET));
    }

    tty_flip_buffer_push(&serial_tty_port);
    tty_kref_put(tty);

    return IRQ_HANDLED;
}

// TTY Operations
static int serial_open(struct tty_struct *tty, struct file *file) {
    tty->driver_data = &serial_tty_port;
    return tty_port_open(&serial_tty_port, tty, file);
}

static void serial_close(struct tty_struct *tty, struct file *file) {
    tty_port_close(&serial_tty_port, tty, file);
}

static int serial_write(struct tty_struct *tty, const unsigned char *buffer, int count) {
    int i;
    uint32_t status;

    for (i = 0; i < count; i++) {
        do {
            status = ioread32(base + (STATUS_REG_OFFSET));
        } while (status & STATUS_TX_FULL_MASK); // Wait for space in TX FIFO

        iowrite32(buffer[i], base + (DATA_REG_OFFSET));
    }

    return count;
}

static unsigned int serial_write_room(struct tty_struct *tty) {
    uint32_t status = ioread32(base + (STATUS_REG_OFFSET));
    return (status & STATUS_TX_FULL_MASK) ? 0 : TTY_BUFFER_SIZE;
}

static const struct tty_operations serial_tty_ops = {
    .open = serial_open,
    .close = serial_close,
    .write = serial_write,
    .write_room = serial_write_room,
};
static int probe(struct platform_device* dev) {
	int result = 0;
	unsigned int irq;
	printk(KERN_INFO "serial isr: probe \n");
	
	irq = irq_of_parse_and_map(dev->dev.of_node, 0);
	printk(KERN_INFO "serial isr: found irq = %d in device tree\n", irq);
	
	result = request_irq(irq, ir, IRQF_SHARED, "serial ip", &dev->dev);
	if(result != 0)
		printk(KERN_INFO "serial iser: request_irq returned %d\n", result);
	else 
		printk(KERN_INFO "serial iser: request_irq was successful");
	
	return result;
}

static int remove(struct platform_device* dev) 
{
	printk(KERN_INFO "serial isr: remove\n");
	
	free_irq(of_irq_get(dev->dev.of_node, 0), &dev->dev);
	
	return 0;
}

static struct of_device_id driver_of_match[] = {
	{.compatible = "xlnx,soc-axi4lite-reserved-j1", },
		{}
};
MODULE_DEVICE_TABLE(of, driver_of_match);

static struct platform_driver driver = {
	.probe = probe,
	.remove = remove,
	.driver = {
		.name = "serial isr",
		.owner = THIS_MODULE,
		.of_match_table = driver_of_match,
	},
};
// Initialization and Exit
static int __init serial_tty_init(void) {
    int ret;

    // Map serial registers
    base = (uint32_t*)ioremap(AXI4_LITE_BASE + SERIAL_BASE_OFFSET, SPAN_IN_BYTES);
    if (!base) {
        printk(KERN_ALERT "Failed to map serial registers\n");
        return -ENOMEM;
    }

    // Allocate TTY driver
    serial_tty_driver = tty_alloc_driver(1, TTY_DRIVER_REAL_RAW | TTY_DRIVER_DYNAMIC_DEV);
    if (!serial_tty_driver) {
        iounmap(base);
        return -ENOMEM;
    }

    serial_tty_driver->driver_name = DEVICE_NAME;
    serial_tty_driver->name = "ttyserial";
    serial_tty_driver->major = TTY_MAJOR;
    serial_tty_driver->minor_start = 0;
    serial_tty_driver->type = TTY_DRIVER_TYPE_SERIAL;
    serial_tty_driver->subtype = SERIAL_TYPE_NORMAL;
    serial_tty_driver->init_termios = tty_std_termios;
    serial_tty_driver->init_termios.c_cflag = B9600 | CS8 | CREAD | HUPCL | CLOCAL;
    tty_set_operations(serial_tty_driver, &serial_tty_ops);

    // Initialize TTY port
    tty_port_init(&serial_tty_port);

    ret = tty_register_driver(serial_tty_driver);
    if (ret) {
        printk(KERN_ALERT "Failed to register TTY driver\n");
        tty_driver_kref_put(serial_tty_driver);
        iounmap(base);
        return ret;
    }
	

    printk(KERN_INFO "Serial TTY driver initialized\n");
    return 0;
}

static void __exit serial_tty_exit(void) {
    tty_unregister_driver(serial_tty_driver);
    tty_port_destroy(&serial_tty_port);
    tty_driver_kref_put(serial_tty_driver);
    iounmap(base);

    printk(KERN_INFO "Serial TTY driver exited\n");
}

module_init(serial_tty_init);
module_exit(serial_tty_exit);

