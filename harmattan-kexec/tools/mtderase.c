/* mtderase - erase eraseblocks of an MTD device (ubiboot's busybox has no flash_erase)
 * usage: mtderase /dev/mtdN <start offset> <number of blocks>  (offset in bytes, hex ok) */
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <mtd/mtd-user.h>

int main(int argc, char **argv)
{
	mtd_info_t mi; erase_info_t ei; int fd, i, n;
	unsigned long start;
	if (argc != 4) { fprintf(stderr, "usage: %s /dev/mtdN start_offset nblocks\n", argv[0]); return 2; }
	start = strtoul(argv[2], NULL, 0); n = atoi(argv[3]);
	fd = open(argv[1], O_RDWR);
	if (fd < 0) { perror(argv[1]); return 1; }
	if (ioctl(fd, MEMGETINFO, &mi)) { perror("MEMGETINFO"); return 1; }
	printf("%s: size %u erasesize %u writesize %u\n", argv[1], mi.size, mi.erasesize, mi.writesize);
	for (i = 0; i < n; i++) {
		ei.start = start + i * mi.erasesize; ei.length = mi.erasesize;
		if (ei.start + ei.length > mi.size) { fprintf(stderr, "beyond device\n"); return 1; }
		if (ioctl(fd, MEMERASE, &ei)) { fprintf(stderr, "erase 0x%x: ", ei.start); perror("MEMERASE"); return 1; }
		printf("erased 0x%x-0x%x\n", ei.start, ei.start + ei.length - 1);
	}
	close(fd);
	return 0;
}
