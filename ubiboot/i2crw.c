/*
 * i2crw - read or write one register of an i2c device through i2c-dev
 *   i2crw BUS ADDR REG          read  (prints the value)
 *   i2crw BUS ADDR REG VAL      write, then read back
 * ADDR/REG/VAL in hex. Uses I2C_SLAVE_FORCE.
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define I2C_SLAVE_FORCE 0x0706

int main(int argc, char **argv)
{
	char dev[32];
	unsigned char b[2];
	int fd, addr, reg;

	if (argc < 4) {
		fprintf(stderr, "usage: %s BUS ADDR REG [VAL]\n", argv[0]);
		return 2;
	}
	snprintf(dev, sizeof dev, "/dev/i2c-%s", argv[1]);
	addr = strtol(argv[2], NULL, 16);
	reg = strtol(argv[3], NULL, 16);
	fd = open(dev, O_RDWR);
	if (fd < 0 || ioctl(fd, I2C_SLAVE_FORCE, addr) < 0) {
		perror(dev);
		return 1;
	}
	if (argc > 4) {
		b[0] = reg;
		b[1] = strtol(argv[4], NULL, 16);
		if (write(fd, b, 2) != 2) {
			perror("write");
			return 1;
		}
	}
	b[0] = reg;
	if (write(fd, b, 1) != 1 || read(fd, b, 1) != 1) {
		perror("read");
		return 1;
	}
	printf("%s 0x%02x reg %02x = %02x\n", dev, addr, reg, b[0]);
	return 0;
}
