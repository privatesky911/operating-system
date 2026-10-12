# HAOS / odroid-m1s（sm3566a 平台）项目交接文档

**最后更新**：2026-10-12
**上一版**：2026-10-10
**工作目录**：`/home/t011/works/hermes/home_assistant/operating-system`（`~` = `/home/t011`）
**构建目标**：`odroid_m1s`，为 **sm3566a**（RK3568 SoC，8GB LPDDR4）硬件平台适配
**构建方式**：Docker-in-Docker（宿主镜像 `hassos:local`）

---

## 0. 接手必读（TL;DR）

| 项 | 状态 |
|----|------|
| 构建 | ✅ 通过（clean build 验证过） |
| 串口控制台 | ✅ 可用：`/dev/ttyUSB0` 1500000 8n1 |
| 以太网 RMII / RTL8201F | ✅ 已修复（见 §5.1） |
| HAOS 镜像产出 | ✅ 已产出（见 §6） |
| **设备 eMMC 当前内容** | ⚠️ **Android OS**（用户在 Windows 上刷入） |
| **HAOS 回刷** | ❌ **未完成**（本次未完成的任务） |
| Linux 侧 Rockchip USB | ❌ bulk 传输 EIO（`RKU_Write err=-1`），rkdeveloptool 不可用（见 §8） |
| Windows 侧 Rockchip USB | ✅ 可用（用户已用 Windows 成功刷 Android） |

**当前最优回刷路径**：Windows 机器 + Rockchip 工具（RKDevTool / AndroidTool），或修复 Linux 侧 USB 后走 UMS 模式（见 §7）。

---

## 1. 项目概览

- 为 **sm3566a**（RK3568，8G LPDDR4，参考 EVB8-LP4-V10）构建 Home Assistant OS
- 以 Hardkernel **odroid-m1s**（RK3566）为目标做平台适配
- 内核：linux-6.18.40（上游 kernel.org）
- Buildroot 子模块：`dfa1d775aa4f26502c4214516050117192aeff12`
- HAOS 版本：**18.3.dev0**（HA Core 2026.8.1，Supervisor 2026.07.5）

## 2. 硬件平台要点

| 项 | 值 |
|----|-----|
| SoC | Rockchip RK3568（板子实际 DTS 显示 RK3566 EVB2 LP4X V10） |
| 内存 | 8GB LPDDR4（U-Boot 里显示 2GiB，取决于 DDR 配置） |
| 以太网 PHY | **RTL8201F**（100M，RMII 模式），reset GPIO3_PA5 |
| PMIC | **RK809** |
| 串口 | UART2（`ttyS2`），1500000 8n1 |
| eMMC | `mmcblk2`（Linux/Android 视角）；U-Boot 里是 `mmc 0` |
| USB OTG | dwc3 `fcc00000.dwc3` |
| sdmmc | `sdhci@fe310000`（U-Boot 里 `mmc 0` 与之并列，见 §8.4） |

## 3. 构建环境与命令

```bash
# 主构建命令
./scripts/enter.sh make -j12 odroid_m1s

# 改了 Dockerfile / scripts/entry.sh 后要重建镜像
docker build -t hassos:local .

# 强制内核重编（手动改 DTS 后必须做，否则不生效）
rm -f output/build/linux-6.18.40/.stamp_configured
rm -f output/build/linux-6.18.40/.stamp_built
rm -f output/images/rk3566-odroid-m1s.dtb
./scripts/enter.sh make -j12 odroid_m1s
# 或直接用仓库里的 ./build_kernel.sh（已封装上面三条）
```

### 3.1 中国网络环境下的构建修复（已完成）

| 文件 | 修复 |
|------|------|
| `scripts/entry.sh` | 内部 dockerd 加 registry-mirrors + GOPROXY |
| `buildroot/package/pkg-golang.mk` | `GOPROXY=direct` → `https://goproxy.cn,direct` |
| `buildroot/fs/common.mk` | rsync 加 `--no-inc-recursive`（EROFS 构建竞态） |
| `Dockerfile` | apt 源 → Aliyun；daemon.json 加大量 registry-mirrors |
| `rootfs-overlay/etc/docker/daemon.json` | registry-mirrors（含 `ghcr.nju.edu.cn`） |

> ⚠️ `buildroot/` 是 git 子模块：`git submodule update` 会**还原** pkg-golang.mk / common.mk 的修改。

## 4. 已修改/新增文件一览（`git status`）

```
 M Dockerfile
 m buildroot                                    (子模块，含 pkg-golang.mk / fs/common.mk 修改)
 M buildroot-external/board/hardkernel/odroid-m1s/cmdline.txt
 M buildroot-external/board/hardkernel/odroid-m1s/uboot.config
 M buildroot-external/rootfs-overlay/etc/containerd/config.toml
 M buildroot-external/rootfs-overlay/etc/docker/daemon.json
 M scripts/entry.sh
?? HANDOFF.md                                   (本文档)
?? build_kernel.sh
?? buildroot-external/board/hardkernel/odroid-m1s/patches/linux/0001-dts-rmii-rtl8201f.patch
?? buildroot-external/board/hardkernel/odroid-m1s/patches/uboot/
?? config.ini                                   (rkdeveloptool pack 用，见 §8.3)
?? rk3566_loader.bin                            (rkdeveloptool 能接受的 loader，见 §8.3)
?? rk3288_bootloader_test.bin                   (pack 自动生成的垃圾，可删)
?? rk3566-yunkong-m6s.dts                       (另一块板子参考 DTS)
?? scripts/flash-ums.sh
?? sm3566a_kernel/                              (参考内核源码树)
```

## 5. 硬件适配详情

### 5.1 以太网（核心工作，已解决）

- **目标文件**：`output/build/linux-6.18.40/arch/arm64/boot/dts/rockchip/rk3566-odroid-m1s.dts`
- **参考**：`sm3566a_kernel/kernel/arch/arm64/boot/dts/rockchip/sm3566a-v0.dts`
- **补丁**：`buildroot-external/board/hardkernel/odroid-m1s/patches/linux/0001-dts-rmii-rtl8201f.patch`
  （同时改 DTS + `drivers/net/ethernet/stmicro/stmmac/stmmac_mdio.c`）

**关键修复**：
1. `phy-mode = "rmii"` + `clock_in_out = "output"`（MAC 向 PHY 输出 50MHz —— 曾用 `"input"` 导致 `Failed to reset the dma`）
2. `assigned-clock-parents` / `gmac1m0` pinmux（GPIO3 组）
3. PHY reset GPIO3_PA5 + reset-delays `<0 20000 100000>`
4. `snps,reset-gpio` / `snps,reset-active-low` / `snps,reset-delays-us`

**验证过的现象**：`PHY [stmmac-0:00] driver [RTL8201F Fast Ethernet]`，`end0` 拿到 IP `192.168.193.128/24`。

### 5.2 rk809 PMIC

- `rockchip,system-power-controller`、`pmic-reset-func = <0>`、`pwrkey` 节点、`rk809_codec` 子节点、DCDC/LDO always-on
- `sound` 节点 `sound-dai = <&rk809_codec>`

### 5.3 串口控制台

`buildroot-external/board/hardkernel/odroid-m1s/cmdline.txt`：
```
console=tty0 console=ttyS2,1500000n8
```
（原只有 `console=tty0`，导致内核日志全丢 HDMI，串口无输出）

### 5.4 U-Boot

- `output/build/uboot-2026.04/arch/arm/mach-rockchip/boot_mode.c`：ADC 检测通道 `1 → 0`；触发改为 `ums 0 mmc 0`
- 补丁：`board/hardkernel/odroid-m1s/patches/uboot/0001-use-adc-channel-0-for-download-key.patch`
- `uboot.config`：`CONFIG_BOOTDELAY=2`（自定义 U-Boot 有 2 秒中断窗口）
- DTS `adc-keys`：saradc 通道 0，vol-up（1750µV）触发 download 模式

> ⚠️ 以上 U-Boot 修改**只对自编译 U-Boot 有效**。设备被官方/Android U-Boot 覆盖后失效（见 §8）。

## 6. 产出镜像

`output/images/`：

| 文件 | 大小 | 说明 |
|------|------|------|
| `haos_odroid-m1s-18.3.dev0.img.xz` | 335M | **完整可烧录镜像**（解压 ~2.2G） |
| `haos_odroid-m1s-18.3.dev0-full.img.xz` | 898M | 含预装应用的完整镜像（见 `../operating-system-full-images/`） |
| `haos_odroid-m1s-18.3.dev0.raucb` | 193M | RAUC OTA 包 |
| `boot.vfat` | 16M | boot 分区 |
| `data.ext4` / `overlay.ext4` | 222M / 96M | 数据/overlay 分区 |
| `kernel.img` / `spl.img` | 15M / 16M | 内核 / SPL |

**已解压好的 raw 镜像**：`/tmp/haos_full.img`（2.2G，来自 `-full.img.xz`）
**相关目录**：`../operating-system-full-images/`（含 `input/` + `output/`，把应用打包进镜像用）

## 7. 烧录方法（按当前可用性排序）

### 方法 A：Windows + RKDevTool（**当前推荐**，因为 Linux 侧 USB 有问题）
用户在 Windows 上已成功刷入 Android，说明 Windows 侧 USB 通路正常。
- 用 RKDevTool 加载 loader + 镜像，或进 UMS/rockusb 后写盘

### 方法 B：UMS 模式（Linux，需修好 USB）
```bash
./scripts/flash-ums.sh                      # 已有脚本
# 或手动：串口 → reboot → 拦 U-Boot → ums 0 mmc 0 → 写 /dev/sda → Ctrl+C → reset
```
⚠️ 脚本里写死 `HAOS>` 提示符和 `ums 0 mmc 0`；换成 Android U-Boot 后提示符/设备号都不同（见 §8.4）。

### 方法 C：rkdeveloptool（Linux，需修好 USB + loader）
```bash
TOOL=<blobs>/tools/rkdeveloptool
sudo $TOOL db rk3566_loader.bin     # 先下载 loader（MASKROM → Loader）
sudo $TOOL wl 0 /tmp/haos_full.img  # 从 LBA 0 写整盘
sudo $TOOL rd                       # 复位
```
⚠️ 必须先 `db` 成功；且 loader 必须是 `rkdeveloptool pack` 产出的（见 §8.3）。

### 方法 D：硬件 MASKROM（短接 eMMC CLK 到 GND 上电）
- 设备进 `2207:350a`；但**仍受 Linux USB bulk 问题阻挡**（见 §8）

## 8. 重要问题与踩坑（2026-10-12 本轮）

### 8.1 设备曾变砖 → 已用 Android 恢复
- 现象：启动循环 `No valid slot found, resetting tries to 3`
- 根因：早前用串口 base64 传 DTB 失败，只写了 **3093 字节**（应为 114802）到 boot 分区
- 现状：用户已用 **Windows 刷入 Android OS**，设备能正常启动

### 8.2 Linux 侧 Rockchip USB bulk 传输失败（**关键阻塞**）
- 现象：设备能枚举（`2207:350a`），描述符能读（控制传输 OK），但**所有 bulk 传输失败**：
  - `rkdeveloptool`：`Error: RKU_Write failed, err=-1` → `Test Device failed!`
  - `pyusb`：`USBError [Errno 5] Input/Output Error`（8/31/64/…/1024 字节全部失败）
- 已排除：软复位（`d.reset()` 无效）、端点 halt、包大小、驱动绑定
- 疑点：设备挂在 **Genesys Logic USB Hub** 后面；**Windows 侧同一硬件可正常刷机** ⇒ 更像是 Linux/xHCI/Hub 侧问题，未必是设备硬件坏
- **未解决**。建议：设备 USB 数据线**直插主机**（不过 Hub）、换线、或换另一台机器

### 8.3 `rkdeveloptool db` 报 "Opening loader failed" 的真正原因（**重要发现**）
- `boot_merger` 生成的 `rk356x_spl_loader_v1.18.112.bin` 会被 rkdeveloptool **拒绝**（解析失败）
- **解法**：用 rkdeveloptool **自带的 pack** 重新打包：
  1. 在 CWD 放 `config.ini`（`[CHIP_NAME] NAME=RK3566`、471=DDR、472=usbplug、LOADER=FlashData/FlashBoot、OUTPUT=PATH）
  2. `cd <cwd> && <blobs>/tools/rkdeveloptool pack`
  3. 产出 `rk3566_loader.bin`（443K）—— 这个 rkdeveloptool 能接受
- 该 config.ini 与生成的 loader 已留在仓库根目录

### 8.4 Android 的 U-Boot 与 HAOS 的不同
- Android 跑的是 **Rockchip U-Boot 2017.09**（`Model: Rockchip RK3568 Evaluation Board`）
- 日志显示：`dwmmc@fe2b0000: 1, dwmmc@fe2c0000: 2, sdhci@fe310000: 0`，`Bootdev(atags): mmc 0`
  ⇒ **eMMC 在 Android U-Boot 里是 `mmc 0`**（与 HAOS 一致，但和 Linux 的 `mmcblk2` 编号不同）
- **该 U-Boot 不响应空格打断 autoboot**；Ctrl+C 会连 `reboot` 命令一起杀掉（`130|console:/ $`）
- 试过 `reboot ums`：Android 接受了（出现重启 spinner），但结果未知（USB 在 Windows 侧无法从 Linux 验证）

### 8.5 非 root 访问 USB 的正确姿势
- udev 规则 `/usr/lib/udev/rules.d/60-rkdeveloptool.rules` 把 Rockchip 设备归到 `rkdeveloptool` 组
- 把用户加入该组后，可免 sudo 用 `sg rkdeveloptool -c '<cmd>'` 访问
- **串口**：`/dev/ttyUSB0` 属 `dialout` 组，用 `sg dialout -c '/usr/bin/python3 …'`

### 8.6 其它历史坑
1. **禁止使用 `~/works/hermes/emuelec/` 下的任何工具/资料**（用户明确要求）
2. dd 到块设备被环境禁止 → 用 Python 写 `/dev/sda` 代替
3. 手动改 DTS **不触发重编** → 必须删 stamp（见 §3）
4. 补丁不能重名冲突（曾两个 `0001` 补丁改同一文件）
5. `upgrade_tool` 无参数运行会进交互模式 → **无限输出**（曾刷出 5.9GB 日志），务必带参数

## 9. 凭据 / 路径速查

| 项 | 值 |
|----|-----|
| 串口 | `/dev/ttyUSB0`，1500000，8n1 |
| 设备 IP（HAOS 时） | `192.168.193.128` |
| SSH（HAOS） | `root@192.168.193.128:22`，公钥已配置 |
| HAOS 串口登录 | 用户名 `root`，密码空（直接回车） |
| Android 串口 | `console:/ $`（uid=2000 shell，非 root） |
| Rockchip USB ID | `2207:350a`（MASKROM/Loader） |
| blobs 目录 | `output/build/rockchip-blobs-b4558da0860ca48bf1a571dd33ccba580b9abe23/` |
| rkdeveloptool | 同上 `tools/rkdeveloptool`（v1.2，官方） |
| pack 用 config.ini | 仓库根 `./config.ini` |
| 可用 loader | 仓库根 `./rk3566_loader.bin` |
| 解压好的镜像 | `/tmp/haos_full.img`（2.2G） |

## 10. 本项目用过的辅助脚本（在 `/tmp/rkdev/`，可能已被清理）

| 脚本 | 用途 |
|------|------|
| `serial_cmd.py` | 通过串口执行命令并打印输出 |
| `ums_enter.py` / `ums_enter2.py` / `ums_enter3.py` | 串口重启 + 拦截 U-Boot（空格 / Ctrl+C 两种） |
| `ums_mode.py` | 发送任意命令（如 `reboot ums`）并监控串口 |
| `usbtest.py` / `usbtest2.py` / `usbreset.py` / `usbclear.py` | pyusb 底层 bulk 传输诊断 |

> 都需 `sg dialout -c '/usr/bin/python3 <脚本>'`（`/usr/bin/python3` 才带 pyserial）

## 11. 下一步建议

1. **优先**：让设备 USB 直插主机（不过 Hub）后，重测 `sg rkdeveloptool -c './rkdeveloptool rci'` 是否通过
   - 通过 → 走 §7 方法 C（`db rk3566_loader.bin` + `wl 0 /tmp/haos_full.img`）
2. 若 Linux 侧始终不通 → 用 **Windows + RKDevTool** 刷 HAOS（用户已证明 Windows 通路可用）
3. 若要保留 Android 可用性，刷 HAOS 前先确认镜像来源为自编译版本（18.3.dev0，含以太网修复）
4. 刷完 HAOS 后回归验证：串口日志 + 以太网 `end0` 拿 IP
5. 未验证项：WiFi（rtl8821cu/8822cu 驱动）、蓝牙音箱（需 Music Assistant 插件）

## 12. 变更记录

- **2026-10-12**：设备砖机 → Windows 刷 Android 恢复；发现 rkdeveloptool loader 打包问题（§8.3）；发现 Linux 侧 USB bulk EIO 阻塞（§8.2）；尝试 UMS（§8.4）；本文档合并更新
- **2026-10-10**：以太网 RMII/RTL8201F 修复完成；U-Boot 烧录按键改造；上一版交接文档
