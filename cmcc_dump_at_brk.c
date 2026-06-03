/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * wxshadow 断点命中：在当前 App 线程内核态 copy_from_user 读 x0 明文 → dmesg (cmcc_plain:)
 * 加载 wxshadow_cmcc.kpm 时 init 参数填: cmcc
 *
 * copy_from_user 必须在模块 init 中解析；断点上下文里调用 kallsyms_lookup_name 可能卡死/重启。
 */
#include "wxshadow_internal.h"
#include "cmcc_dump_at_brk.h"

int cmcc_plain_enabled;

#define CMCC_PLAIN_MAX_DUMP 8192
#define CMCC_PLAIN_CHUNK     240
#define CMCC_PLAIN_MAX_CHUNKS   8

/* AArch64 用户态地址粗校验（避免断点误命中时 copy 非法指针） */
#define CMCC_USER_ADDR_MIN  0x10000UL
#define CMCC_USER_ADDR_MAX  0x00ffffffffffffUL

static unsigned long (*cmcc_copy_from_user_fn)(void *to, const void __user *from,
                                             unsigned long n);

static int cmcc_user_ptr_ok(const void __user *p, unsigned long len)
{
    unsigned long addr = (unsigned long)p;

    if (!p || addr < CMCC_USER_ADDR_MIN || addr > CMCC_USER_ADDR_MAX)
        return 0;
    if (!len || len > CMCC_PLAIN_MAX_DUMP)
        return 0;
    if (addr + len < addr)
        return 0;
    if (addr + len > CMCC_USER_ADDR_MAX)
        return 0;
    return 1;
}

static unsigned long cmcc_plain_len_from_regs(struct pt_regs *regs)
{
    u64 lo = regs->regs[0];
    u64 hi = regs->regs[3];
    u64 alt = regs->regs[5];
    unsigned long len;

    if (hi > lo && hi - lo > 0 && hi - lo <= CMCC_PLAIN_MAX_DUMP)
        len = (unsigned long)(hi - lo);
    else if (alt > lo && alt - lo > 0 && alt - lo <= CMCC_PLAIN_MAX_DUMP)
        len = (unsigned long)(alt - lo);
    else
        len = 4096;

    if (!cmcc_user_ptr_ok((const void __user *)(unsigned long)lo, len))
        return 0;
    return len;
}

int cmcc_plain_setup(void)
{
    cmcc_copy_from_user_fn = (void *)kallsyms_lookup_name("copy_from_user");
    if (!cmcc_copy_from_user_fn)
        cmcc_copy_from_user_fn = (void *)kallsyms_lookup_name("__copy_from_user");
    if (!cmcc_copy_from_user_fn) {
        pr_err("wxshadow: cmcc_plain: copy_from_user not found, dump disabled\n");
        cmcc_plain_enabled = 0;
        return -1;
    }
    pr_info("wxshadow: cmcc_plain: copy_from_user ready\n");
    return 0;
}

static long cmcc_copy_user(void *kdst, const void __user *usrc, unsigned long n)
{
    if (!cmcc_copy_from_user_fn || !n || n > CMCC_PLAIN_CHUNK)
        return -1;
    return (long)cmcc_copy_from_user_fn(kdst, usrc, n);
}

void cmcc_plain_dump_at_brk(struct pt_regs *regs)
{
    const void __user *uptr;
    unsigned long total, off;
    char kbuf[CMCC_PLAIN_CHUNK + 1];
    int printable = 1;
    unsigned int chunks = 0;

    if (!cmcc_plain_enabled || !regs || !cmcc_copy_from_user_fn)
        return;

    if (regs->regs[0] < CMCC_USER_ADDR_MIN)
        return;

    uptr = (const void __user *)(unsigned long)regs->regs[0];
    total = cmcc_plain_len_from_regs(regs);
    if (!total)
        return;

    pr_info("cmcc_plain: ======== dump start len=%lu ptr=%px ========\n",
            total, uptr);

    for (off = 0; off < total && off < CMCC_PLAIN_MAX_DUMP; off += CMCC_PLAIN_CHUNK) {
        unsigned long chunk = total - off;

        if (++chunks > CMCC_PLAIN_MAX_CHUNKS)
            break;
        printable = 1;

        if (chunk > CMCC_PLAIN_CHUNK)
            chunk = CMCC_PLAIN_CHUNK;
        if (!cmcc_user_ptr_ok(uptr + off, chunk))
            break;

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
