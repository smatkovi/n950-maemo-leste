/* cachebench: effective CPU clock + pointer-chase latency per working-set size.
 * Cortex-A8: dependent ADD chain = 1 cycle/add -> measures the real clock.
 * Pointer chase over a random cyclic permutation of 64-byte lines -> ns/load.
 * Min of several repeats to filter out background load. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdint.h>

static double now(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/* 32 dependent adds per iteration */
static __attribute__((noinline)) void addchain(unsigned long iters)
{
	unsigned long x = 0;
	__asm__ volatile(
		"1:\n"
		".rept 32\n add %0, %0, #1\n .endr\n"
		"subs %1, %1, #1\n"
		"bne 1b\n"
		: "+r"(x), "+r"(iters) : : "cc");
}

#define LINE 64

int main(int argc, char **argv)
{
	int reps = argc > 1 ? atoi(argv[1]) : 7;
	unsigned long iters = 2000000; /* 64M adds */
	double best = 1e9;
	int r;
	for (r = 0; r < reps; r++) {
		double t0 = now();
		addchain(iters);
		double t = now() - t0;
		if (t < best) best = t;
	}
	double ns_per_cycle = best * 1e9 / (iters * 32.0);
	printf("clock: %.1f MHz (%.3f ns/cycle)\n", 1000.0 / ns_per_cycle, ns_per_cycle);

	static const unsigned sizes_k[] = { 8, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512, 1024, 2048, 4096, 8192 };
	unsigned i;
	printf("%8s %9s %9s\n", "size", "ns/load", "cyc/load");
	for (i = 0; i < sizeof(sizes_k) / sizeof(sizes_k[0]); i++) {
		size_t bytes = (size_t)sizes_k[i] * 1024;
		size_t n = bytes / LINE, k;
		char *buf;
		size_t *perm;
		if (posix_memalign((void **)&buf, 4096, bytes)) return 1;
		memset(buf, 0, bytes);
		perm = malloc(n * sizeof(*perm));
		for (k = 0; k < n; k++) perm[k] = k;
		srand(12345);
		for (k = n - 1; k > 0; k--) {
			size_t j = (size_t)rand() % (k + 1), t = perm[k];
			perm[k] = perm[j]; perm[j] = t;
		}
		for (k = 0; k < n; k++)
			*(void **)(buf + perm[k] * LINE) = buf + perm[(k + 1) % n] * LINE;
		free(perm);

		unsigned long steps = 1000000;
		void **p = (void **)buf;
		/* warm up */
		for (k = 0; k < n * 2; k++) p = (void **)*p;
		double bt = 1e9;
		for (r = 0; r < reps; r++) {
			unsigned long s = steps;
			double t0 = now();
			while (s--) p = (void **)*p;
			double t = now() - t0;
			if (t < bt) bt = t;
		}
		if (!p) puts("");
		double ns = bt * 1e9 / steps;
		printf("%7uK %9.2f %9.1f\n", sizes_k[i], ns, ns / ns_per_cycle);
		free(buf);
	}
	return 0;
}
