/*
 * l2fix: report the Cortex-A8 cache control registers and, with enable=1,
 * set ACTLR.L2EN (bit 1) the way the UbiBoot/openmode "l2fix" does in
 * cpu_v7_proc_init.  ubiboot's kernel clears L2EN in cpu_v7_proc_fin before
 * kexec and the Harmattan PR1.3 kernel never sets it again, so a kexec'd
 * MeeGo runs without L2.  The caches are cleaned+invalidated (all levels, by
 * set/way) with interrupts off right before the bit is set.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/irqflags.h>
#include <asm/cacheflush.h>

static int enable;
module_param(enable, int, 0444);
MODULE_PARM_DESC(enable, "1 = set ACTLR.L2EN");

#define RD(name, op) static inline u32 name(void) { u32 v; asm volatile(op : "=r"(v)); return v; }
RD(rd_midr,   "mrc p15, 0, %0, c0, c0, 0")
RD(rd_sctlr,  "mrc p15, 0, %0, c1, c0, 0")
RD(rd_actlr,  "mrc p15, 0, %0, c1, c0, 1")
RD(rd_nsacr,  "mrc p15, 0, %0, c1, c1, 2")
RD(rd_l2aux,  "mrc p15, 1, %0, c9, c0, 2")
RD(rd_clidr,  "mrc p15, 1, %0, c0, c0, 1")
RD(rd_idpfr1, "mrc p15, 0, %0, c0, c1, 1")

static void report(const char *when)
{
	u32 a = rd_actlr(), s = rd_sctlr();
	printk(KERN_INFO "l2fix %s: MIDR=%08x SCTLR=%08x (C=%d I=%d Z=%d) ACTLR=%08x (L2EN=%d) "
	       "NSACR=%08x L2AUX=%08x CLIDR=%08x ID_PFR1=%08x\n", when,
	       rd_midr(), s, !!(s & 4), !!(s & 0x1000), !!(s & 0x800), a, !!(a & 2),
	       rd_nsacr(), rd_l2aux(), rd_clidr(), rd_idpfr1());
}

static int __init l2fix_init(void)
{
	unsigned long flags;
	u32 before, after;

	report("now");
	if (!enable)
		return 0;
	local_irq_save(flags);
	flush_cache_all();
	before = rd_actlr();
	asm volatile("mcr p15, 0, %0, c1, c0, 1\n\tisb" : : "r"(before | 2) : "memory");
	after = rd_actlr();
	local_irq_restore(flags);
	printk(KERN_INFO "l2fix: ACTLR %08x -> %08x, L2 %s\n", before, after,
	       (after & 2) ? "ENABLED" : "still off (write ignored)");
	report("after");
	return 0;
}

static void __exit l2fix_exit(void)
{
	report("unload");
}

module_init(l2fix_init);
module_exit(l2fix_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Report/enable Cortex-A8 L2 cache after kexec (N9/N950)");
