// Software FIFO and Interrupt Handling
// Serial IP 
// Serial IP ISR Default Handler (serial_isr.c)
// Olajumoke Aboderin

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
#include <asm/io.h>
#include "../address_map.h"
#include "serial_regs.h"

uint32_t *serial = NULL;

#define FIFO_SIZE 1024

// Kernel module information

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Olajumoke Aboderin");
MODULE_DESCRIPTION("Serial IP Interrupt Handler");

//ISR

static char fifo[FIFO_SIZE];
static int wr_index = 0, rd_index = 0;

static irqreturn_t isr(int irq, void *dev_id) {
    while (!(ioread32(serial + STATUS_REG_OFFSET) & RXFE)) {
        char data = ioread32(serial + DATA_REG_OFFSET);
        fifo[wr_index] = data;
        wr_index = (wr_index + 1) % FIFO_SIZE;
    }
    return IRQ_HANDLED;
}

static ssize_t rx_data_show(struct device *dev, struct device_attribute *attr, char *buffer) {
    if (wr_index == rd_index) {
        return sprintf(buffer, "-1\n"); // Empty FIFO
    }
    char data = fifo[rd_index];
    rd_index = (rd_index + 1) % FIFO_SIZE;
    return sprintf(buffer, "%c\n", data);
}

static int probe(struct platform_device* dev) {
	int result = 0;
	unsigned int irq;
	printk(KERN_INFO "serial isr: probe \n");
	
	irq = irq_of_parse_and_map(dev->dev.of_node, 0);
	printk(KERN_INFO "serial isr: found irq = %d in device tree\n", irq);
	
	result = request_irq(irq, isr, IRQF_SHARED, "serial ip", &dev->dev);
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

static int __init initialize_module(void)
{
	if(platform_driver_register(&driver)){
		printk(KERN_WARNING "serial isr: failed to register platform driver\n");
		return -1;
	}
	printk(KERN_INFO "serial isr: registered platform driver\n");
	
	serial = (uint32_t*)ioremap(serial + SERIAL_BASE_OFFSET, SPAN_IN_BYTES);
	if(serial == NULL){
		printk(KERN_WARNING "serial isr: ioremap failed\n");
		return -EIO;
	}
	printk(KERN_INFO "serial isr: ioremap returned 0x%p\n", serial);
	printk(KERN_INFO "serial isr: initialize done\n");
	
	return 0;	
}


static void __exit exit_module(void)
{
	platform_driver_unregister(&driver);
	printk(KERN_INFO "serial isr: exit\n");
}

module_init(initialize_module);
module_exit(exit_module);



	
	
	
