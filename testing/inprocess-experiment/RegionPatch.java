package com.mtk.utils;

import java.io.FileInputStream;
import java.io.FileOutputStream;

import com.philips.bluray.media.util.NativeCopier;
import com.philips.bluray.system.RegisterAccess;

// Put ARM register stubs in an executable allocation and redirect the
// JbiMiscProxy target (fixed address 0x010fec00) to them, then set PSR 20 = 7.
public class RegionPatch extends Thread {
    // Self-contained ARM stubs; each returns 0 on success, 1 on out-of-range.
    // setpsr: *g_psr[reg] = value        (g_psr = *(0x010fc27c))
    private static final String S_SETPSR =
        "800051e30400002a14309fe5003093e5012183e70000a0e31eff2fe10100a0e31eff2fe17cc20f01";
    // getpsr: *out = g_psr[reg]
    private static final String S_GETPSR =
        "800051e30500002a18309fe5003093e5013193e7003082e50000a0e31eff2fe10100a0e31eff2fe17cc20f01";
    // setgpr: *(g_psr-0x4000)[reg] = value
    private static final String S_SETGPR =
        "010a51e30500002a18309fe5003093e5013943e2012183e70000a0e31eff2fe10100a0e31eff2fe17cc20f01";
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
        w("/mnt/sda1/patch_started.txt", "started\n");
        new RegionPatch().start();
    }

    // PSR 20 value from /mnt/sda1/psr20_value.txt (first digit), default 7.
    // Change the file on the stick (or over the LAN) instead of rebuilding.
    private static int regionValue() {
        try {
            FileInputStream f = new FileInputStream("/mnt/sda1/psr20_value.txt");
            int c = f.read();
            f.close();
            if (c >= '1' && c <= '9') {
                return c - '0';
            }
        } catch (Throwable t) {
        }
        return 7;
    }

    public void run() {
        try {
            Thread.sleep(10000);
        } catch (Throwable t) {
        }
        StringBuffer log = new StringBuffer();
        try {
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
                int setgpr = 0x120;
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

                int v1 = -1;
                try {
                    v1 = RegisterAccess.getPSR(20);
                } catch (Throwable t) {
                    log.append("getPSR1 err ").append(t.toString()).append("\n");
                }
                log.append("get20 before=").append(v1).append("\n");
                int want = regionValue();
                log.append("value file=").append(want).append("\n");
                if (v1 != 1 && v1 != 2 && v1 != 4) {
                    log.append("stub value not sane, set skipped\n");
                } else {
                    try {
                        RegisterAccess.setPSR(20, want);
                    } catch (Throwable t) {
                        log.append("setPSR err ").append(t.toString()).append("\n");
                    }
                }
                int v2 = -1;
                try {
                    v2 = RegisterAccess.getPSR(20);
                } catch (Throwable t) {
                    log.append("getPSR2 err ").append(t.toString()).append("\n");
                }
                log.append("get20 after=").append(v2).append("\n");
            }
        } catch (Throwable t) {
            log.append("FATAL ").append(t.toString()).append("\n");
        }
        w("/mnt/sda1/patch_result.txt", log.toString());
    }
}
