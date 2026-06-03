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

### 前置（加载失败时先看这里）

- 已用 **APatch 对当前内核完成补丁**（不是只装 App），且为 **ARM64、内核 3.18–6.1**。
- APatch / KernelPatch 设置里开启 **syscall-table-hook**、**inline-hook**（wxshadow 依赖 `hook_syscalln`、`hook_wrap*` 等导出符号）。
- 若曾加载过同名模块：先 **卸载 `wxshadow`**，再加载 `wxshadow_cmcc.kpm`。
- 参数 `cmcc` 只影响明文 dump，**与能否加载无关**；排查时可先留空试加载。

### 加载失败怎么查

PC 连接手机后运行：

```cmd
diagnose_kpm.bat
```

或在加载失败后立刻执行：

```bash
adb shell su -c "dmesg | grep -E 'KP |wxshadow' | tail -80"
```

| dmesg 现象 | 处理 |
|------------|------|
| `KP E unknown symbol: hook_syscalln`（或 `hook_wrap`、`fp_wrap_syscalln`） | 内核补丁未导出 KPM API → 用新版 APatch **重新 Embed/补丁**，并打开上述 hook 选项 |
| `wxshadow: failed to resolve symbols` | 内核版本/厂商 ROM 与 wxshadow 扫描不兼容，换机或换 KP 版本 |
| `wxshadow: failed to hook exit_mmap` / `prctl` | 同上，或 KP 与编译时不一致 |
| 无任何 `wxshadow:` 日志 | 可能在 ELF 阶段就失败，只看 `KP E` 行 |
| `load_module: wxshadow exist` | **不是失败**：旧模块仍在，须先 **卸载 wxshadow** 再加载 `wxshadow_cmcc.kpm` |

`wxshadow_cmcc.kpm` 与上游 `wxshadow.kpm` 模块名都是 **`wxshadow`**，不能两份同时存在。APatch 界面显示「加载失败」经常是 `exist` 导致。

卸载后重新加载，init 参数填 `cmcc`，`dmesg` 应出现：

```text
wxshadow: cmcc plain dump ENABLED (dmesg tag cmcc_plain)
```

断点命中后除寄存器外还应有 `cmcc_plain:` 行。

### 一加载就卡死/重启

多为 **内核 panic** 或 **断点风暴**，按顺序做（不要跳过重启）：

1. **关机再开**（不要只软重启），进系统后先 **不要** 自动加载 KPM。
2. APatch 里 **卸载** `wxshadow`（若有 `Nohello` 等其它 KPM，先只保留必要的一个做对比）。
3. **强制停止**中国移动 App，避免旧 shadow 断点残留：

   ```bash
   adb shell am force-stop com.greenpoint.android.mc10086.activity
   ```

4. 先 **无参数** 加载 `wxshadow_cmcc.kpm` 试能否稳定；成功后再 **卸载并重载**，参数填 `cmcc`。
5. 确认 `dmesg` 有 `cmcc_plain: copy_from_user ready` 再跑 `hook.bat`。
6. 若 **无 cmcc 的上游 wxshadow.kpm** 也重启 → 机型与 wxshadow 不兼容，用 Frida（`hook_encrypt_frida.js`）代替。

旧版在断点里每次 `kallsyms_lookup_name` 可能在部分 5.15 机型上触发死锁；新构建已改为 **init 时解析符号**。

### 正常使用

1. APatch → 加载 `dist/wxshadow_cmcc.kpm`，初始化参数：**`cmcc`**
2. 打开中国移动 App

## PC 设断点

```cmd
hook.bat
```

换 APK 版本：改 `hook.bat` 里 `LibnetOff`（默认 `133d0`，encrypt 符号偏移）。

## 不抓真机

用 unidbg：`ChinaMobileNetClient`（见 `scripts/README.md`）。
