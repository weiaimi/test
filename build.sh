#!/usr/bin/env bash
# 构建 wxshadow_cmcc.kpm + wxshadow_client (Android arm64)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$SCRIPT_DIR/dist"
WORK="${WORK_DIR:-$SCRIPT_DIR/_build/mkpms}"
MKPMS_REPO="${MKPMS_REPO:-https://github.com/kkkbbb/mkpms.git}"
MKPMS_REF="${MKPMS_REF:-master}"

install_cross_tools() {
  if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    if [ -f /etc/debian_version ]; then
      echo "[*] apt install aarch64-linux-gnu compiler"
      sudo apt-get update -qq
      sudo apt-get install -y -qq gcc-aarch64-linux-gnu
    fi
  fi

  if command -v aarch64-none-elf-gcc >/dev/null 2>&1 \
     && command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    return 0
  fi

  TOOLCHAIN_URL="${TOOLCHAIN_URL:-https://developer.arm.com/-/media/Files/downloads/gnu/13.3.rel1/binrel/arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-elf.tar.xz}"
  TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$SCRIPT_DIR/_build/toolchain}"
  if [ ! -x "$TOOLCHAIN_DIR/bin/aarch64-none-elf-gcc" ]; then
    echo "[*] download aarch64-none-elf toolchain"
    mkdir -p "$(dirname "$TOOLCHAIN_DIR")"
    TAR="$(mktemp).tar.xz"
    curl -fsSL -o "$TAR" "$TOOLCHAIN_URL"
    tar -xf "$TAR" -C "$(dirname "$TOOLCHAIN_DIR")"
    rm -f "$TAR"
    EXTRACTED="$(find "$(dirname "$TOOLCHAIN_DIR")" -maxdepth 1 -type d -name 'arm-gnu-toolchain-*' | head -1)"
    [ -n "$EXTRACTED" ] && [ -x "$EXTRACTED/bin/aarch64-none-elf-gcc" ] || {
      echo "[!] toolchain extract failed"
      exit 1
    }
    rm -rf "$TOOLCHAIN_DIR"
    mv "$EXTRACTED" "$TOOLCHAIN_DIR"
  fi
  export PATH="$TOOLCHAIN_DIR/bin:$PATH"
}

install_cross_tools
command -v aarch64-none-elf-gcc >/dev/null || { echo "[!] missing aarch64-none-elf-gcc"; exit 1; }
command -v aarch64-linux-gnu-gcc >/dev/null || { echo "[!] missing aarch64-linux-gnu-gcc"; exit 1; }

echo "[*] kpm compiler: $(aarch64-none-elf-gcc -dumpversion)"
echo "[*] client compiler: $(aarch64-linux-gnu-gcc -dumpversion)"

rm -rf "$WORK"
git clone --branch "$MKPMS_REF" --recursive "$MKPMS_REPO" "$WORK"

if [ ! -e "$WORK/kernel" ] && [ -d "$WORK/.kp" ]; then
  echo "[*] init KernelPatch submodule"
  git -C "$WORK" submodule update --init --recursive
fi
if [ ! -d "$WORK/kernel" ] && [ -d "$WORK/.kp/kernel" ]; then
  ln -sf .kp/kernel "$WORK/kernel" || cp -a "$WORK/.kp/kernel" "$WORK/kernel"
fi
[ -d "$WORK/kernel" ] || { echo "[!] kernel headers missing under $WORK"; exit 1; }

bash "$SCRIPT_DIR/apply_overlay.sh" "$WORK"

mkdir -p "$WORK/build"
cd "$WORK/build"
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=Generic \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_C_COMPILER=aarch64-none-elf-gcc \
  -G Ninja

ninja wxshadow.kpm

KPM_SRC=""
for p in \
  "$WORK/build/kpms/wxshadow/wxshadow.kpm" \
  "$WORK/build/wxshadow.kpm"; do
  if [ -f "$p" ]; then KPM_SRC="$p"; break; fi
done
[ -n "$KPM_SRC" ] || { echo "[!] wxshadow.kpm not found"; find "$WORK/build" -name '*.kpm'; exit 1; }

mkdir -p "$DIST"
cp -f "$KPM_SRC" "$DIST/wxshadow_cmcc.kpm"

aarch64-linux-gnu-gcc -static -O2 -s -D_GNU_SOURCE \
  -o "$DIST/wxshadow_client" \
  "$WORK/kpms/wxshadow/wxshadow_client.c"

file "$DIST/wxshadow_cmcc.kpm" "$DIST/wxshadow_client" || true
echo "[OK] artifacts:"
ls -la "$DIST"
sha256sum "$DIST"/* 2>/dev/null || true
