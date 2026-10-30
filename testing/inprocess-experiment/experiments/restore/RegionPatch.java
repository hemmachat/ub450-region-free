package com.mtk.utils;

import java.io.FileInputStream;
import java.io.FileOutputStream;

import com.philips.bluray.media.util.NativeCopier;
import com.philips.bluray.system.RegisterAccess;

// Put ARM register stubs in an executable allocation and redirect the
// JbiMiscProxy target (fixed address 0x010fec00) to them, then set PSR 20 to the first number in /mnt/sda1/psr20_value.txt (default 1). Reads PSR 20 through the player's own interface first and skips the patch when it already matches, so a later disc start in the same session leaves disc menus alone (29 Oct 2026).
public class RegionPatch extends Thread {
    // Self-contained ARM stubs; each returns 0 on success, 1 on out-of-range.
    // setpsr: *g_psr[reg] = value        (g_psr = *(0x010fc27c))
    private static final String S_SETPSR =
        "800051e30400002a14309fe5003093e5012183e70000a0e31eff2fe10100a0e31eff2fe17cc20f01";
    // getpsr: *out = g_psr[reg]
    private static final String S_GETPSR =
        "800051e30500002a18309fe5003093e5013193e7003082e50000a0e31eff2fe10100a0e31eff2fe17cc20f01";
    // setgpr: *(g_psr-0x4000)[reg] = value
    // setgpr with two magic registers: 0xf00 runs the object scan, 0xf01
    // reads the word at GPR[3010] into GPR[3011]. The scan target is stored
    // XORed with the mask in the scratch block so the block itself cannot
    // match, which lets the scan cover the heap the buffer lives in.
    private static final String S_SETGPR =
        "010a51e30a0000aa0f0c51e30a00000a01cf00e30c0051e13300000af0309fe5003093e5013943e2012183e70000a0e31eff2fe10100a0e31eff2fe1f0472de9d0409fe5005094e5046094e50c0094e5006026e008a094e5b4309fe5003093e5013943e20020a0e3107084e20080a0e3ffffffea050058e1170000aa889187e0041099e5009099e5010059e1100000aa000099e5060050e10100000a049089e2f8ffffea0a0059e10700009a0920a0e10c0099e5f0ce02e30c0083e7100099e5f4ce02e30c0083e7030000ea049089e2ecffffea018088e2e5ffffeaec0e02e3002083e70000a0e3f087bde820309fe5003093e5013943e208cf02e30c2093e7002092e50ccf02e30c2083e70000a0e31eff2fe17cc20f0111111111";
    // getgpr: *out = *(g_psr-0x4000)[reg]
    private static final String S_GETGPR =
        "010a51e30600002a1c309fe5003093e5013943e2013193e7003082e50000a0e31eff2fe10100a0e31eff2fe17cc20f01";
    private static final String S_NOOP = "0000a0e31eff2fe1";

    private static void w(String path, String s) {
        try {
            FileOutputStream f = new FileOutputStream(path);
            f.write(s.getBytes());
            f.close();
        } catch (Throwable t) {
        }
    }

    private static String rd(String path, int max) {
        StringBuffer sb = new StringBuffer();
        try {
            FileInputStream f = new FileInputStream(path);
            byte[] b = new byte[4096];
            int n;
            int total = 0;
            while ((n = f.read(b)) > 0 && total < max) {
                sb.append(new String(b, 0, n));
                total += n;
            }
            f.close();
        } catch (Throwable t) {
            sb.append("ERR ").append(t.toString());
        }
        return sb.toString();
    }

    private static byte[] bytes(String h) {
        int n = h.length() / 2;
        byte[] b = new byte[n];
        for (int i = 0; i < n; i++) {
            b[i] = (byte) Integer.parseInt(h.substring(i * 2, i * 2 + 2), 16);
        }
        return b;
    }

    private static void put32(byte[] b, int off, long v) {
        b[off] = (byte) (v & 0xff);
        b[off + 1] = (byte) ((v >> 8) & 0xff);
        b[off + 2] = (byte) ((v >> 16) & 0xff);
        b[off + 3] = (byte) ((v >> 24) & 0xff);
    }

    private static void copy(byte[] dst, int off, byte[] src) {
        for (int i = 0; i < src.length; i++) {
            dst[off + i] = src[i];
        }
    }

    // executable bit of the mapping that contains addr
    private static boolean isExec(String maps, long addr) {
        int p = 0;
        while (p < maps.length()) {
            int e = maps.indexOf('\n', p);
            if (e < 0) {
                e = maps.length();
            }
            String line = maps.substring(p, e);
            p = e + 1;
            int dash = line.indexOf('-');
            int sp = line.indexOf(' ');
            if (dash > 0 && sp > dash && line.length() >= sp + 5) {
                try {
                    long s = Long.parseLong(line.substring(0, dash), 16);
                    long en = Long.parseLong(line.substring(dash + 1, sp), 16);
                    if (addr >= s && addr < en) {
                        return line.charAt(sp + 3) == 'x';
                    }
                } catch (Throwable t) {
                }
            }
        }
        return false;
    }

    public static void go() {
        w("/mnt/sda1/patch_started.txt", "started dryrun3\n");
        new RegionPatch().start();
    }

    // PSR 20 value from /mnt/sda1/psr20_value.txt (0-255), default 1.
    // Value 1 plays locked region A discs and the lax locked B disc used in
    // testing; 7 makes strict A discs refuse. Never use values above 7.
    // Java 1.4 constructs only: this runs on the player's CVM.
    private static int parseValue(int c0, int c1, int c2) {
        int v = 0;
        int n = 0;
        if (c0 >= '0' && c0 <= '9') {
            v = c0 - '0';
            n = 1;
        }
        if (n == 1 && c1 >= '0' && c1 <= '9') {
            v = v * 10 + (c1 - '0');
            n = 2;
        }
        if (n == 2 && c2 >= '0' && c2 <= '9') {
            v = v * 10 + (c2 - '0');
            n = 3;
        }
        if (n == 0 || v > 255) {
            return -1;
        }
        return v;
    }

    private static int valueOrDefault(int v) {
        if (v >= 0) {
            return v;
        }
        return 1;
    }

    // The register only has to be set once per session; skipping the patch
    // when it already holds the value keeps the player's own interface in
    // place, which is what keeps a disc menu that is still up working.
    private static boolean alreadySet(int now, int want) {
        return now == want;
    }

    private static int regionValue() {
        int v = -1;
        try {
            FileInputStream f = new FileInputStream("/mnt/sda1/psr20_value.txt");
            int c0 = f.read();
            int c1 = f.read();
            int c2 = f.read();
            f.close();
            v = parseValue(c0, c1, c2);
        } catch (Throwable t) {
        }
        return valueOrDefault(v);
    }

    private static final int MAX_RANGES = 200;
    private static final long SCAN_MASK = 0x5A5A5A5AL;

    private static boolean inRegion(String maps, long v, char flag) {
        int p = 0;
        while (p < maps.length()) {
            int e = maps.indexOf('\n', p);
            if (e < 0) {
                e = maps.length();
            }
            String line = maps.substring(p, e);
            p = e + 1;
            int dash = line.indexOf('-');
            int sp = line.indexOf(' ');
            if (dash > 0 && sp > dash && line.length() > sp + 4) {
                if (line.substring(sp + 1, sp + 4).indexOf(flag) >= 0) {
                    try {
                        long s = Long.parseLong(line.substring(0, dash), 16);
                        long en = Long.parseLong(line.substring(dash + 1, sp), 16);
                        if (v >= s && v < en) {
                            return true;
                        }
                    } catch (Throwable t) {
                    }
                }
            }
        }
        return false;
    }

    private static long readWord(long addr) {
        try {
            RegisterAccess ra = RegisterAccess.getInstance();
            ra.setGPR(3010, (int) addr);
            ra.setGPR(0xF01, 0);
            return ra.getGPR(3011) & 0xFFFFFFFFL;
        } catch (Throwable t) {
            return 0;
        }
    }

    private static boolean exists(String path) {
        try {
            new FileInputStream(path).close();
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    // Find the player's adapter object: scan every writable mapping (heap
    // included) for its vtable pointer and accept only a match whose +0x10
    // backend is a real writable pointer whose own first word is a code
    // pointer. +0xc is logged but not required.
    private static long findAdapter(String maps, long buf, StringBuffer log) {
        long[] starts = new long[MAX_RANGES];
        long[] ends = new long[MAX_RANGES];
        int n = 0;
        int p = 0;
        while (p < maps.length() && n < MAX_RANGES) {
            int e = maps.indexOf('\n', p);
            if (e < 0) {
                e = maps.length();
            }
            String line = maps.substring(p, e);
            p = e + 1;
            int dash = line.indexOf('-');
            int sp = line.indexOf(' ');
            if (dash > 0 && sp > dash && line.length() > sp + 4) {
                if (line.substring(sp + 1, sp + 4).indexOf('w') >= 0) {
                    try {
                        long s = Long.parseLong(line.substring(0, dash), 16);
                        long en = Long.parseLong(line.substring(dash + 1, sp), 16);
                        if (en > s
                                && line.indexOf("/dev/bdkmem") < 0
                                && line.indexOf("/dev/osai") < 0
                                && line.indexOf("[stack") < 0) {
                            starts[n] = s;
                            ends[n] = en;
                            n++;
                        }
                    } catch (Throwable t) {
                    }
                }
            }
        }
        log.append("scan ranges=").append(n).append("\n");
        if (n == 0) {
            return 0;
        }
        byte[] sc = new byte[0x10 + MAX_RANGES * 8];
        long skip = 0;
        long found = 0;
        int passing = 0;
        for (int attempt = 0; attempt < 24; attempt++) {
            put32(sc, 0, n);
            put32(sc, 4, 0xC92B20L ^ SCAN_MASK);
            put32(sc, 8, skip);
            put32(sc, 0xC, SCAN_MASK);
            for (int i = 0; i < n; i++) {
                put32(sc, 0x10 + i * 8, starts[i]);
                put32(sc, 0x10 + i * 8 + 4, ends[i]);
            }
            NativeCopier.copyToNative(sc, 0, 0x10 + n * 8, buf + 0x800);
            long obj = 0;
            long m1 = 0;
            long m2 = 0;
            try {
                RegisterAccess ra = RegisterAccess.getInstance();
                ra.setGPR(0xF00, 0);
                obj = ra.getGPR(3003) & 0xFFFFFFFFL;
                m1 = ra.getGPR(3004) & 0xFFFFFFFFL;
                m2 = ra.getGPR(3005) & 0xFFFFFFFFL;
            } catch (Throwable t) {
                log.append("scan err ").append(t.toString()).append("\n");
                break;
            }
            if (obj == 0) {
                break;
            }
            boolean m2ok = (obj & 3L) == 0 && m2 != 0 && (m2 & 3L) == 0 && inRegion(maps, m2, 'w');
            long vptr = 0;
            if (m2ok) {
                vptr = readWord(m2);
            }
            boolean ok = m2ok && vptr != 0 && (vptr & 1L) == 0 && inRegion(maps, vptr, 'x');
            log.append("cand=").append(Long.toString(obj, 16))
                    .append(" m0c=").append(Long.toString(m1, 16))
                    .append(" m10=").append(Long.toString(m2, 16))
                    .append(" vt=").append(Long.toString(vptr, 16))
                    .append(ok ? " ok" : " reject").append("\n");
            if (ok) {
                passing++;
                found = obj;
            }
            skip = obj + 4;
        }
        log.append("passing=").append(passing).append("\n");
        return passing == 1 ? found : 0;
    }

    public void run() {
        try {
            Thread.sleep(10000);
        } catch (Throwable t) {
        }
        StringBuffer log = new StringBuffer();
        try {
            int want = regionValue();
            int now = -1;
            // Read through the player's own interface, before it is replaced.
            try {
                now = RegisterAccess.getPSR(20);
            } catch (Throwable t) {
                log.append("getPSR0 err ").append(t.toString()).append("\n");
            }
            log.append("get20 before=").append(now).append("\n");
            log.append("value file=").append(want).append("\n");
            if (alreadySet(now, want)) {
                // The register only has to be set once per session. Replacing
                // the player's interface again would freeze a disc menu that is
                // still up (Jigsaw, 29 Oct 2026), so leave it alone.
                log.append("already set, patch skipped\n");
                log.append("get20 after=").append(now).append("\n");
            } else if (now != 1 && now != 2 && now != 4) {
                log.append("stub value not sane, set skipped\n");
            } else {
                long buf = NativeCopier.allocate(0, 4096);
                if (buf == 0) {
                    buf = NativeCopier.allocate(1, 4096);
                }
                String maps = rd("/proc/self/maps", 400000);
                w("/mnt/sda1/patch_maps.txt", maps);
                log.append("buf=").append(Long.toString(buf, 16)).append("\n");
                if (buf == 0 || (buf & 3L) != 0) {
                    log.append("bad alloc\n");
                } else if (!isExec(maps, buf)) {
                    log.append("buf not executable\n");
                } else {
                    byte[] b = new byte[4096];
                    int noop = 0x90;
                    int setpsr = 0xC0;
                    int getpsr = 0xF0;
                    int setgpr = 0x200;
                    int getgpr = 0x150;
                    put32(b, 0, buf + 0x10);
                    for (int i = 0; i < 32; i++) {
                        put32(b, 0x10 + i * 4, buf + noop);
                    }
                    put32(b, 0x10 + 2 * 4, buf + getgpr);
                    put32(b, 0x10 + 3 * 4, buf + setgpr);
                    put32(b, 0x10 + 4 * 4, buf + getpsr);
                    put32(b, 0x10 + 5 * 4, buf + setpsr);
                    copy(b, noop, bytes(S_NOOP));
                    copy(b, setpsr, bytes(S_SETPSR));
                    copy(b, getpsr, bytes(S_GETPSR));
                    copy(b, setgpr, bytes(S_SETGPR));
                    copy(b, getgpr, bytes(S_GETGPR));
                    put32(b, setgpr + 0x118, buf + 0x800);
                    NativeCopier.copyToNative(b, 0, 4096, buf);
                    // ARM I/D caches are not coherent: thrash the D-cache so the
                    // stub lines are evicted to L2 before the first fetch.
                    byte[] thrash = new byte[2097152];
                    for (int i = 0; i < thrash.length; i++) {
                        thrash[i] = (byte) i;
                    }
                    byte[] p = new byte[4];
                    put32(p, 0, buf);
                    NativeCopier.copyToNative(p, 0, 4, 0x010fec00L);
                    log.append("target written\n");

                    try {
                        RegisterAccess.setPSR(20, want);
                    } catch (Throwable t) {
                        log.append("setPSR err ").append(t.toString()).append("\n");
                    }
                    int v2 = -1;
                    try {
                        v2 = RegisterAccess.getPSR(20);
                    } catch (Throwable t) {
                        log.append("getPSR2 err ").append(t.toString()).append("\n");
                    }
                    log.append("get20 after=").append(v2).append("\n");
                    long obj = findAdapter(maps, buf, log);
                    boolean enable = exists("/mnt/sda1/restore_enable.txt");
                    log.append("obj=").append(Long.toString(obj, 16)).append("\n");
                    log.append("restore enabled=").append(enable).append("\n");
                    w("/mnt/sda1/patch_result.txt", log.toString());
                    if (obj != 0 && enable) {
                        put32(p, 0, obj);
                        NativeCopier.copyToNative(p, 0, 4, 0x010fec00L);
                        log.append("restored=").append(Long.toString(obj, 16)).append("\n");
                        try {
                            log.append("get20 real=").append(RegisterAccess.getPSR(20)).append("\n");
                        } catch (Throwable t) {
                            log.append("getPSR3 err ").append(t.toString()).append("\n");
                        }
                    } else if (obj != 0) {
                        log.append("dry run, not restoring\n");
                    } else {
                        log.append("no single candidate, interface left replaced\n");
                    }
                }
            }
        } catch (Throwable t) {
            log.append("FATAL ").append(t.toString()).append("\n");
        }
        w("/mnt/sda1/patch_result.txt", log.toString());
    }
}
