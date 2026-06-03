/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef CMCC_DUMP_AT_BRK_H
#define CMCC_DUMP_AT_BRK_H

struct pt_regs;

extern int cmcc_plain_enabled;
void cmcc_plain_dump_at_brk(struct pt_regs *regs);

#endif
