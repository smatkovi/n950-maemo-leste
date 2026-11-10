/*
 * n950-fm-bt -- route the WL1273's audio interface to its FM receiver.
 *
 * The N950's FM sound comes over the WL1273's I2S port (the sound card
 * "N950 FM", McBSP4). The chip drives that port only after a Bluetooth
 * vendor command, HCI opcode 0xfc00 with the parameters f3 88 01 02, which
 * FM radio apps under Harmattan send before they record; Bluetooth has to be
 * on for it. This switches hci0 on if needed, sends the command and waits
 * for its status. Raw HCI needs CAP_NET_RAW, switching hci0 on CAP_NET_ADMIN:
 * the package gives this program both as file capabilities.
 *
 * Exit status 0 when the controller accepted the command.
 */
#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#ifndef AF_BLUETOOTH
#define AF_BLUETOOTH	31
#endif
#define BTPROTO_HCI	1
#define SOL_HCI		0
#define HCI_FILTER	2
#define HCIDEVUP	_IOW('H', 201, int)

#define HCI_COMMAND_PKT	0x01
#define HCI_EVENT_PKT	0x04
#define EVT_CMD_COMPLETE 0x0e
#define EVT_CMD_STATUS	0x0f
#define EVT_VENDOR	0xff

struct sockaddr_hci {
	sa_family_t hci_family;
	unsigned short hci_dev;
	unsigned short hci_channel;
};

struct hci_filter {
	uint32_t type_mask;
	uint32_t event_mask[2];
	uint16_t opcode;
};

static void flt_event(struct hci_filter *f, unsigned event)
{
	unsigned bit = event & 63;

	f->event_mask[bit >> 5] |= 1u << (bit & 31);
}

static long ms_now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(void)
{
	static const uint8_t cmd[] = {
		HCI_COMMAND_PKT, 0x00, 0xfc, 4, 0xf3, 0x88, 0x01, 0x02
	};
	struct sockaddr_hci addr = { .hci_family = AF_BLUETOOTH, .hci_dev = 0 };
	struct hci_filter flt = { .type_mask = 1 << HCI_EVENT_PKT };
	int fd, ok = 0;
	long end;

	fd = socket(AF_BLUETOOTH, SOCK_RAW | SOCK_CLOEXEC, BTPROTO_HCI);
	if (fd < 0) {
		perror("n950-fm-bt: socket");
		return 1;
	}
	if (ioctl(fd, HCIDEVUP, 0) < 0 && errno != EALREADY) {
		perror("n950-fm-bt: switching hci0 on");
		return 1;
	}
	/* the kernel's filter has 64 event bits: event & 63 */
	flt_event(&flt, EVT_CMD_COMPLETE);
	flt_event(&flt, EVT_CMD_STATUS);
	flt_event(&flt, EVT_VENDOR);
	if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
	    setsockopt(fd, SOL_HCI, HCI_FILTER, &flt, sizeof(flt)) < 0) {
		perror("n950-fm-bt: hci0");
		return 1;
	}
	if (write(fd, cmd, sizeof(cmd)) != sizeof(cmd)) {
		perror("n950-fm-bt: sending the command");
		return 1;
	}

	end = ms_now() + 2000;
	while (!ok && ms_now() < end) {
		struct pollfd p = { .fd = fd, .events = POLLIN };
		uint8_t ev[260];
		ssize_t n;

		if (poll(&p, 1, end - ms_now()) <= 0)
			break;
		n = read(fd, ev, sizeof(ev));
		if (n < 3 || ev[0] != HCI_EVENT_PKT)
			continue;
		/* Command Status: status, credits, opcode */
		if (ev[1] == EVT_CMD_STATUS && n >= 7 && ev[5] == 0x00 &&
		    ev[6] == 0xfc) {
			if (ev[3] != 0) {
				fprintf(stderr, "n950-fm-bt: refused, status 0x%02x\n",
					ev[3]);
				return 1;
			}
			ok = 1;
		}
		/* Command Complete: credits, opcode, status */
		if (ev[1] == EVT_CMD_COMPLETE && n >= 7 && ev[4] == 0x00 &&
		    ev[5] == 0xfc) {
			if (ev[6] != 0) {
				fprintf(stderr, "n950-fm-bt: refused, status 0x%02x\n",
					ev[6]);
				return 1;
			}
			ok = 1;
		}
	}
	close(fd);
	if (!ok)
		fprintf(stderr, "n950-fm-bt: no answer from hci0\n");
	return ok ? 0 : 1;
}
