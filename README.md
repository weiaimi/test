# 中国移动 encrypt 明文（wxshadow KPM）

目录就这些，push 后 GitHub Actions 可直接编译。

| 文件 | 用途 |
|------|------|
| `cmcc_dump_at_brk.c/h` | KPM hook 源码 |
| `build.sh` | 编译（Linux / CI） |
| `dist/wxshadow_cmcc.kpm` | APatch 加载，**参数填 `cmcc`** |
| `dist/wxshadow_client` | `adb push` 到 `/data/local/tmp/` |

## 编译

GitHub **Actions → Build cmcc-wxshadow KPM**，下载 artifact。

```bash
chmod +x build.sh apply_overlay.sh
./build.sh
```

```bash
adb push dist/wxshadow_client /data/local/tmp/
adb shell su -c chmod 755 /data/local/tmp/wxshadow_client
```

## 手机

1. APatch → 加载 `dist/wxshadow_cmcc.kpm`，初始化参数：**`cmcc`**
2. 打开中国移动 App

## PC 设断点

```cmd
cd scripts\cmcc-wxshadow
hook.bat
```

换 APK 版本：改 `hook.bat` 里 `LibnetOff`（默认 `133d0`，encrypt 符号偏移）。

## 不抓真机

用 unidbg：`ChinaMobileNetClient`（见 `scripts/README.md`）。
