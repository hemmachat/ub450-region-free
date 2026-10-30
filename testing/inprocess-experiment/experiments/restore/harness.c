/* Bare-metal harness: run the restore stubs under qemu-system-arm (-M virt).
 *
 * The stub is copied to RAM and its two absolute literals are repointed at
 * harness memory (the player's 0x010fc27c is not mapped on virt); everything
 * else - branches, loops, offsets - is the shipped instruction stream.
 *
 * Layout:
 *   0x40100000  stub code        0x401E0000  scratch block
 *   0x401F0000  g_psr global     0x40200000  GPR array
 *   0x40210000  fake heap
 */

typedef unsigned int u32;

#define STUB_ADDR   0x40100000u
#define SCRATCH     0x401E0000u
#define GPSR_GLOBAL 0x401F0000u
#define GPR_BASE    0x40200000u
#define HEAP        0x40210000u

#define GPR_WORDS   4096u
#define LIT_GPSR    0x114u   /* literal offsets inside the blob */
#define LIT_SCRATCH 0x118u

#include "blob.h"

static void out(const char *s)
{
    volatile unsigned char *uart = (volatile unsigned char *)0x09000000u;
    while (*s) {
        *uart = (unsigned char)*s++;
    }
}

static void outhex(u32 v)
{
    const char *digits = "0123456789abcdef";
    char buf[11];
    int i;
    buf[0] = '0';
    buf[1] = 'x';
    for (i = 0; i < 8; i++) {
        buf[2 + i] = digits[(v >> ((7 - i) * 4)) & 0xF];
    }
    buf[10] = 0;
    out(buf);
}

static u32 rd(u32 addr) { return *(volatile u32 *)addr; }
static void wr(u32 addr, u32 v) { *(volatile u32 *)addr = v; }
static u32 gpr(int i) { return rd(GPR_BASE + 4u * (u32)i); }
static void gpr_set(int i, u32 v) { wr(GPR_BASE + 4u * (u32)i, v); }

static int failures;

static void check(const char *name, u32 want, u32 got)
{
    out(want == got ? "PASS " : "FAIL ");
    out(name);
    if (want != got) {
        out(" want=");
        outhex(want);
        out(" got=");
        outhex(got);
        failures++;
    }
    out("\n");
}

static void setup(u32 count, u32 target, u32 skip, u32 start, u32 end)
{
    u32 i;
    for (i = 0; i < GPR_WORDS; i++) {
        gpr_set((int)i, 0);
    }
    for (i = 0; i < 0x40000u / 4u; i++) {
        wr(HEAP + 4u * i, 0);
    }
    for (i = 0; i < sizeof(stub_blob); i++) {
        *(volatile unsigned char *)(STUB_ADDR + i) = stub_blob[i];
    }
    wr(STUB_ADDR + LIT_GPSR, GPSR_GLOBAL);
    wr(STUB_ADDR + LIT_SCRATCH, SCRATCH);
    wr(GPSR_GLOBAL, GPR_BASE + 0x4000u);
    wr(SCRATCH + 0, count);
    wr(SCRATCH + 4, target ^ 0x5A5A5A5Au);
    wr(SCRATCH + 8, skip);
    wr(SCRATCH + 0xC, 0x5A5A5A5Au);
    wr(SCRATCH + 0x10, start);
    wr(SCRATCH + 0x14, end);
    __asm__ volatile("dsb\n isb\n" ::: "memory");
}

static int call_stub(int reg, int value)
{
    int (*fn)(int, int, int) = (int (*)(int, int, int))STUB_ADDR;
    return fn(0, reg, value);
}

static void make_object(u32 addr, u32 m0c, u32 m10)
{
    wr(addr, 0xC92B20u);
    wr(addr + 0x0C, m0c);
    wr(addr + 0x10, m10);
}

int main(void)
{
    u32 r;

    /* 1. scan finds the object and returns its members */
    setup(1, 0xC92B20u, 0, HEAP, HEAP + 0x40000u);
    make_object(HEAP + 0x5000u, HEAP + 0x100u, HEAP + 0x200u);
    r = (u32)call_stub(0xF00, 0);
    check("scan return 0", 0, r);
    check("scan object", HEAP + 0x5000u, gpr(3003));
    check("scan m0c", HEAP + 0x100u, gpr(3004));
    check("scan m10", HEAP + 0x200u, gpr(3005));

    /* 2. the skip word moves to the next match */
    setup(1, 0xC92B20u, HEAP + 0x5000u, HEAP, HEAP + 0x40000u);
    make_object(HEAP + 0x5000u, HEAP + 0x100u, HEAP + 0x200u);
    make_object(HEAP + 0x9000u, HEAP + 0x300u, HEAP + 0x400u);
    r = (u32)call_stub(0xF00, 0);
    check("skip return 0", 0, r);
    check("skip object", HEAP + 0x9000u, gpr(3003));

    /* 3. no match returns 0 */
    setup(1, 0xC92B20u, 0, HEAP, HEAP + 0x40000u);
    r = (u32)call_stub(0xF00, 0);
    check("no match returns 0", 0, gpr(3003));

    /* 4. read-word mode */
    setup(1, 0xC92B20u, 0, HEAP, HEAP + 0x40000u);
    make_object(HEAP + 0x5000u, HEAP + 0x100u, HEAP + 0x200u);
    gpr_set(3010, HEAP + 0x5000u);
    r = (u32)call_stub(0xF01, 0);
    check("read return 0", 0, r);
    check("read word", 0xC92B20u, gpr(3011));

    /* 5. the normal setgpr path still writes */
    setup(1, 0xC92B20u, 0, HEAP, HEAP + 0x40000u);
    r = (u32)call_stub(5, 0x1234);
    check("setgpr return 0", 0, r);
    check("setgpr wrote", 0x1234u, gpr(5));

    /* 6. out-of-range register is rejected */
    setup(1, 0xC92B20u, 0, HEAP, HEAP + 0x40000u);
    r = (u32)call_stub(0x1000, 7);
    check("bounds return 1", 1, r);

    out(failures ? "RESULT FAIL\n" : "RESULT PASS\n");
    for (;;) { }
}

__asm__(".global _start\n_start:\n ldr sp, =0x48000000\n bl main\n b .\n");
