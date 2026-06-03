/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * wxshadow 断点命中：在当前 App 线程内核态 copy_from_user 读 x0 明文 → dmesg (cmcc_plain:)
 * 加载 wxshadow_cmcc.kpm 时 init 参数填: cmcc
 */
#include "wxshadow_internal.h"
#include "cmcc_dump_at_brk.h"

int cmcc_plain_enabled;

#define CMCC_PLAIN_MAX_DUMP 8192
#define CMCC_PLAIN_CHUNK     240

static unsigned long cmcc_plain_len_from_regs(struct pt_regs *regs)
{
    u64 lo = regs->regs[0];
    u64 hi = regs->regs[3];
    u64 alt = regs->regs[5];

    if (hi > lo && hi - lo > 0 && hi - lo <= CMCC_PLAIN_MAX_DUMP)
        return (unsigned long)(hi - lo);
    if (alt > lo && alt - lo > 0 && alt - lo <= CMCC_PLAIN_MAX_DUMP)
        return (unsigned long)(alt - lo);
    return 4096;
}

static long cmcc_copy_user(void *kdst, const void __user *usrc, unsigned long n)
{
    unsigned long (*copy_from_user_fn)(void *to, const void __user *from,
                                       unsigned long n);

    if (!n || n > CMCC_PLAIN_CHUNK)
        return -1;

    copy_from_user_fn = (void *)kallsyms_lookup_name("copy_from_user");
    if (!copy_from_user_fn)
        copy_from_user_fn = (void *)kallsyms_lookup_name("__copy_from_user");
    if (!copy_from_user_fn)
        return -1;

    return (long)copy_from_user_fn(kdst, usrc, n);
}

void cmcc_plain_dump_at_brk(struct pt_regs *regs)
{
    const void __user *uptr;
    unsigned long total, off;
    char kbuf[CMCC_PLAIN_CHUNK + 1];
    int printable = 1;

    if (!cmcc_plain_enabled || !regs)
        return;

    if (regs->regs[0] < 0x10000)
        return;

    uptr = (const void __user *)(unsigned long)regs->regs[0];
    total = cmcc_plain_len_from_regs(regs);

    pr_info("cmcc_plain: ======== dump start len=%lu ptr=%px ========\n",
            total, uptr);

    for (off = 0; off < total && off < CMCC_PLAIN_MAX_DUMP; off += CMCC_PLAIN_CHUNK) {
        unsigned long chunk = total - off;
        printable = 1;

        if (chunk > CMCC_PLAIN_CHUNK)
            chunk = CMCC_PLAIN_CHUNK;
        memset(kbuf, 0, sizeof(kbuf));
        if (cmcc_copy_user(kbuf, uptr + off, chunk) != 0) {
            pr_info("cmcc_plain: copy failed at off=%lu\n", off);
            break;
        }
        kbuf[chunk] = '\0';
        for (unsigned long i = 0; i < chunk; i++) {
            unsigned char c = (unsigned char)kbuf[i];
            if (c != '\n' && c != '\r' && c != '\t' && (c < 0x20 || c > 0x7e)) {
                if (c != 0)
                    printable = 0;
            }
        }
        if (printable)
            pr_info("cmcc_plain: %s\n", kbuf);
        else
            pr_info("cmcc_plain: (chunk %lu, %lu bytes, non-printable)\n", off, chunk);
        if (chunk < CMCC_PLAIN_CHUNK)
            break;
    }
    pr_info("cmcc_plain: ======== dump end ========\n");
}
