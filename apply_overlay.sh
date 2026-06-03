#!/usr/bin/env bash
# 将 CMCC 明文 dump 并入 mkpms/kpms/wxshadow
set -euo pipefail

MKPMS_ROOT="${1:?usage: apply_overlay.sh <mkpms-root>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WX="$MKPMS_ROOT/kpms/wxshadow"

if [ ! -d "$WX" ]; then
  echo "[!] missing $WX — check mkpms clone"
  exit 1
fi

echo "[*] overlay -> $WX"
cp -f "$SCRIPT_DIR/cmcc_dump_at_brk.c" "$SCRIPT_DIR/cmcc_dump_at_brk.h" "$WX/"

if ! grep -q 'cmcc_dump_at_brk.h' "$WX/wxshadow_handlers.c"; then
  sed -i '/#include "wxshadow_internal.h"/a #include "cmcc_dump_at_brk.h"' "$WX/wxshadow_handlers.c"
fi

if ! grep -q 'cmcc_plain_dump_at_brk' "$WX/wxshadow_handlers.c"; then
  sed -i '/pr_info("wxshadow: ================================\\n");/a\	cmcc_plain_dump_at_brk(regs);' "$WX/wxshadow_handlers.c" || true
  if ! grep -q 'cmcc_plain_dump_at_brk' "$WX/wxshadow_handlers.c"; then
    python3 - "$WX/wxshadow_handlers.c" <<'PY'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8", errors="replace").read().splitlines(True)
out, done = [], False
for line in lines:
    out.append(line)
    if not done and "wxshadow: ================================" in line and "pr_info" in line:
        out.append("\tcmcc_plain_dump_at_brk(regs);\n")
        done = True
if not done:
    raise SystemExit("handlers patch failed")
open(path, "w", encoding="utf-8").writelines(out)
print("[*] patched wxshadow_handlers.c (python)")
PY
  fi
fi

if ! grep -q 'cmcc_dump_at_brk.h' "$WX/wxshadow.c"; then
  sed -i '/#include "wxshadow_internal.h"/a #include "cmcc_dump_at_brk.h"' "$WX/wxshadow.c"
fi

if ! grep -q 'cmcc_plain_enabled' "$WX/wxshadow.c"; then
  python3 <<'PY' "$WX/wxshadow.c"
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8", errors="replace").read()
block = (
    '\tcmcc_plain_enabled = 0;\n'
    '\tif (args && (strstr(args, "cmcc") || strstr(args, "plain"))) {\n'
    '\t\tcmcc_plain_enabled = 1;\n'
    '\t\tpr_info("wxshadow: cmcc plain dump ENABLED (dmesg tag cmcc_plain)\\n");\n'
    '\t}\n\n'
)
for needle in ('\tpr_info("wxshadow: initializing', ' pr_info("wxshadow: initializing', 'pr_info("wxshadow: initializing'):
    if needle in text:
        break
else:
    raise SystemExit("wxshadow.c init needle not found")
if 'cmcc_plain_enabled' not in text:
    text = text.replace(needle, block + needle, 1)
    open(path, "w", encoding="utf-8").write(text)
    print("[*] patched wxshadow.c init")
PY
fi

if ! grep -q 'cmcc_dump_at_brk.c' "$WX/CMakeLists.txt"; then
  sed -i '/wxshadow_scan\.c/a\    cmcc_dump_at_brk.c' "$WX/CMakeLists.txt"
fi

sed -i 's/^add_executable(wxshadow_client/# cmcc_ci: &/' "$WX/CMakeLists.txt"
sed -i 's/^target_link_options(wxshadow_client/# cmcc_ci: &/' "$WX/CMakeLists.txt"

grep -q 'cmcc_plain_dump_at_brk' "$WX/wxshadow_handlers.c" || { echo "[!] handlers patch missing"; exit 1; }
grep -q 'cmcc_plain_enabled' "$WX/wxshadow.c" || { echo "[!] wxshadow.c patch missing"; exit 1; }
grep -q 'cmcc_dump_at_brk.c' "$WX/CMakeLists.txt" || { echo "[!] CMakeLists patch missing"; exit 1; }

echo "[OK] overlay applied"
