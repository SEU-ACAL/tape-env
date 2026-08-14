# SRAM 集成

## TSMC28

调用 `soc-generator` 目标时设置 `USE_TSMC28_SRAM=1`，可将顶层时序存储器替换为
`tsmc28_sram_library.mdf.json` 中的离散宏：

```sh
make -C soc-generator SIM=vcs USE_TSMC28_SRAM=1 verilog
```

该 Makefile 片段使用 `--mode strict`，若任一顶层时序存储器无法映射至列出的单端口宏，
生成会失败。宏库采用 TSMC 的 `CLK/CEB/WEB/A/D/Q` 接口，其中 `CEB` 与 `WEB` 为低有效；
所需的 `RTSEL` 和 `WTSEL` 引脚被固定为每个宏的特征化默认值。

`tsmc28_sram_sim.sources` 会展开为构建目录中的文件列表，包含用于 VCS 或 Verilator 的
`ssg0p81v125c` TSMC 时序模型。可通过 `TSMC28_SRAM_ROOT`、`TSMC28_SRAM_MDF` 与
`TSMC28_SRAM_SIM_SOURCES` 适配其他安装位置或生成的宏集合。

综合时，应为生成的 `*.top.mems.v` 报告的每个宏添加 `NLDM/*_ssg0p81v125c.lib`。布局布线时，
添加匹配的 `LEF/*.lef` 和 `GDSII/*.gds`，并保持相同的宏模块名。不得将仿真 Verilog 模型用作
综合源。

## SMIC180

设置 `USE_SMIC180_SRAM=1`，可将 `TapeoutConfig` 的顶层时序存储器替换为 SMIC S018SP 宏：

```sh
make -C soc-generator SIM=vcs USE_SMIC180_SRAM=1 verilog
```

位于 `chipyard.mk` 默认路径的 SMIC 库提供 `TapeoutConfig` 所使用的六种宏尺寸。宏采用
`CLK/CEN/WEN/A/D/Q` 接口，其中 `CEN` 和 `WEN` 为低有效。`smic180_sram_sim.sources` 会展开为
对应 Verilog 模型。默认 `SMIC180_SRAM_SIM_FLAGS=+notimingcheck` 保留功能仿真并关闭库的时序
检查；时序签核应使用 SDF 或 STA。可通过 `SMIC180_SRAM_ROOT`、`SMIC180_SRAM_MDF`、
`SMIC180_SRAM_SIM_SOURCES` 与 `SMIC180_SRAM_SIM_FLAGS` 适配其他库交付版本。

一次构建只能选择一种硬 SRAM 工艺；TSMC28 流程仍可通过 `USE_TSMC28_SRAM=1` 使用。

## SMIC180 BootROM

`TapeoutConfig` 默认保留原来的可综合 ROM。设置 `USE_SMIC180_ROM=1` 后，会以
S018VM 的固定 `8192x64` 宏 `S018VM_X512Y16D64_PM` 替换 BootROM，并以 `128x64`
宏 `S018VM_X8Y16D64_PM` 替换 JTAG Debug Module 的 Debug ROM。后者物理容量为
1 KiB，其中仅前 128B 是 Debug ROM 镜像，其余内容补零：

```sh
make -C soc-generator/sims/verilator CONFIG=TapeoutConfig \
  USE_SMIC180_ROM=1 verilog
```

默认 CDK 目录为 `/data2/smic180/S018VM_V0P1PC_CDK`，可用
`SMIC180_ROM_CDK_DIR=/path/to/S018VM_V0P1PC_CDK` 覆盖。启用后会由该目录下的
`S018VM.jar` 直接生成两份 ROM IP；默认固定缓存于
`/data2/smic180/rom-ip/{bootrom,debugrom}`，其中包括 Verilog、物理交付物、稳定
codefile 和 fingerprint。仅当对应 BootROM/Debug ROM 的内容、宏规格、compiler JAR
或生成脚本变更时，才重新调用 ROM compiler；否则直接复用缓存。可用
`SMIC180_ROM_CACHE_DIR=/path/to/rom-ip` 覆盖缓存根目录。不使用压缩包，也不会修改 CDK。
默认缓存根目录的权限为 `1777`，输出目录及产物为所有用户可写；可分别通过
`SMIC180_ROM_CACHE_MODE` 和 `SMIC180_ROM_OUTPUT_MODE` 覆盖。
Debug ROM 使用同步 64-bit 宏，并在请求后的下一个周期返回对应的 64-bit word。
`USE_SMIC180_ROM=0`（默认）不生成厂商 ROM
模型。P2E 配置会忽略该选项，始终保留普通 ROM。S018VM compiler 需要 Java 8；默认 `nix develop` 会提供并设置
`SMIC180_ROM_JAVA`。需要固定 Java 时可传 `SMIC180_ROM_JAVA=/path/to/java`。

## TapeoutConfig 检查

选择工艺库前，先检查 `TapeoutConfig` 的实际 SRAM 规格；`mrw` 需按 `mask_gran` 分解为
独立的单端口宏：

```sh
sed -n '1,200p' \
  soc-generator/sims/vcs/generated-src/chipyard.harness.TestHarness.TapeoutConfig/\
chipyard.harness.TestHarness.TapeoutConfig.top.mems.conf
```

当前配置需要 `32x21`、`512x8`、`512x32`、`512x64`、`64x21`、`64x22` 单端口宏；其中
64-bit masked D-cache 会分解为八个 `512x8` 宏。严格模式下，所选库的 MDF、仿真 Verilog
filelist 和物理交付物必须覆盖这些规格。

若使用独立的 TSMC28 宏库交付，在命令中同时覆盖三个变量：

```sh
make -C soc-generator/sims/vcs CONFIG=TapeoutConfig USE_TSMC28_SRAM=1 \
  TSMC28_SRAM_ROOT=/path/to/sram-library \
  TSMC28_SRAM_MDF=/path/to/sram-library.mdf.json \
  TSMC28_SRAM_SIM_SOURCES=/path/to/sram-sim.sources \
  verilog
```

使用 SMIC180 SRAM 替换后，对 `TapeoutConfig` 执行端到端 VCS JTAG 冒烟测试的步骤见
[VCS_JTAG_CN.md](VCS_JTAG_CN.md)。
