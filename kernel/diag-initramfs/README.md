# The diagnostic kernel's initramfs

A busybox shell for the N950's diagnostic kernel (kernel/build.sh with
`DIAG=1`), built into the kernel. `init` collects the boot log and the
eMMC's state, and runs a VEMMC power-cycle test if the eMMC is missing. It
writes all of that to the screen, to the USB serial console and, once the
eMMC works, to p4's `/boot/diag-dmesg.txt`. Then it gives a shell on the
USB serial console (`ttyGS0`).

    BUSYBOX_ROOT=<root with sbin/busybox and lib/> OUT=<dir> \
        bash kernel/diag-initramfs/build.sh
    DIAG=1 WORK=<work> INITRAMFS="<dir>/root <dir>/nodes.list" bash kernel/build.sh

On the PC the console is `/dev/serial/by-id/*Gadget_Serial*`; open it
before or during the boot, since the log is written to it only while the PC
has it open.

It is built in because MOSLO's kexec (2012) places an external initrd
where the decompressed 6.18 kernel overwrites it ("Couldn't find valid RAM
disk image").

## Starting it

The kernel is started by kexec from MOSLO, which NOLO starts from RAM:

1. With the N950 switched off and the cable in, run
   `flasher -k zImage-moslo -l -b`. MOSLO then exports p4 as a USB disk
   and offers a root shell at telnet 192.168.2.15.
2. Copy the kernel to p4's `/boot`.
3. In MOSLO's shell, `mount -o ro /dev/mmcblk0p4 /mnt`, then
   `kexec -l /mnt/boot/<zImage-dtb> --command-line="..."` and `kexec -e`.

A direct NOLO boot of the 6.18 kernel stays dark (2026-11-02), and so far
nothing shows why.
