# SRAM 集成

## TSMC28

调用 `soc-generator` 目标时设置 `USE_TSMC28_SRAM=1`，可将顶层时序存储器替换为
`tsmc28_sram_library.mdf.json` 中的离散宏：

```sh
make -C soc-generator SIM=vcs USE_TSMC28_SRAM=1 verilog
```

该 Makefile 片段使用 `--mode strict`，若任一顶层时序存储器无法映射至列出的宏，
生成会失败。宏库采用 TSMC 的 `CLK/CEB/WEB/A/D/Q` 接口，其中 `CEB` 与 `WEB` 为低有效；
所需的 `RTSEL` 和 `WTSEL` 引脚被固定为每个宏的特征化默认值。

`tsmc28_sram_sim.sources` 会展开为构建目录中的文件列表，包含用于 VCS 或 Verilator 的
`ssg0p81v125c` TSMC 时序模型。可通过 `TSMC28_SRAM_ROOT`、`TSMC28_SRAM_MDF` 与
`TSMC28_SRAM_SIM_SOURCES` 适配其他安装位置或生成的宏集合。

综合时，应为生成的 `*.top.mems.v` 报告的每个宏添加 `NLDM/*_ssg0p81v125c.lib`。布局布线时，
添加匹配的 `LEF/*.lef` 和 `GDSII/*.gds`，并保持相同的宏模块名。不得将仿真 Verilog 模型用作
综合源。

### FDIP Mega 独立宏库

`FDIPMegaBoomV3Config`、`FDIPMegaBoomV3PerfConfig` 和其 `Cosim` 系列配置
自动选择 `TSMC28_SRAM_PROFILE=fdip`；硬宏替换仍需显式启用：

```sh
make -C soc-generator/sims/verilator CONFIG=FDIPMegaBoomV3Config \
  USE_TSMC28_SRAM=1 verilog
```

FDIP profile 使用 `fdip_tsmc28_sram_library.mdf.json`、
`fdip_tsmc28_sram_sim.sources` 和 `/data2/TSMC28/Memory/SRAM/fdip-20261014/`。
库有 13 种实际宏，208 个 NLDM `.lib/.db`（每种 16 corner）；SS/TT/FF 的 SRAM
名称分别为 `ssg0p81v125c`、`tt0p9v85c`、`ffg1p05vm40c`。
其他配置默认保留 `TSMC28_SRAM_PROFILE=legacy`。自定义 FDIP 配置可显式选择 profile。

UHDDPSRAM 原始硬宏有两个 RW 口和一个共同 CLK，MDF 固定 A 读/B 写：
`CEBA=~R0_en`、`WEBA=1`、`CEBB=~W0_en`、`WEBB=0`；
`QA` 返回读数据，`QB` 不连接。A 口的 `DA/BWEBA` 固定 0，读模式下不参与写入。
物理 mask granularity 为 1，MacroCompiler 将逻辑 field mask 展开为逐 bit 的
低有效 `BWEBB`。`RTSEL/WTSEL/PTSEL` 固定 0；单口宏按各自 datasheet 设置
`RTSEL/WTSEL`，不能沿用双口常量。

映射前 `check-fdip-tsmc28-clocks.py` 沿生成层级检查所有 1R1W 实例的读写时钟同源，
不支持的表达式或不同的时钟都会拒绝映射。MDF 只将物理 CLK 绑定到 W0_clk；
这项检查是保持 R0_clk 语义的必要条件。

当前生成 RTL 的 14 种逻辑 memory 各对应一个宏，全 ChipTop 共 80 个宏实例；
`FDIPBoomFrontend` 中有 50 个（BPU 17、ICache 33），合计 54.625 KiB 的宏容量。
这些是生成层级数量；综合后还需核查。FTQ、RAS 和其他未声明为同步 memory 的
状态不在这 50 个 SRAM 中。

14 种映射模块和生产 RTL 的 5 种 folded 布局均已连接原厂 PDK 模型通过功能验证。
功能测试使用 `TSMC_CM_UNIT_DELAY/UNIT_DELAY`，不证明 1 GHz timing。
不要将硬宏生成目录与已有 synflops simulator 混用；更改映射后需重新构建 simulator。

工作台提供独立 `tsmc28_fdip` profile，以及前端独立综合脚本：

```sh
python3 /data1/GB/ic_workbench/2-SYN/scripts/run_fdip_frontend.py \
  --generated soc-generator/sims/verilator/generated-src/chipyard.harness.TestHarness.FDIPMegaBoomV3Config \
  --output /path/to/new-run --period 1.0
```

脚本冻结前端 RTL 和运行约束，使用真实 SS `.db`，保留 hierarchy，输出 netlist、DDC、
SDC、SDF、面积、时序和 vectorless power 报告。目标是 pre-layout；没有 extracted RC、
CTS 或 workload activity。SS/FF STA 脚本为工作台的
`4-Pre_PR_STA_POWER/scripts/pt_fdip_frontend.tcl`。生产映射和回归证据保存在
`analysis/fdip-tsmc28-mapping-20261014/`。

## SMIC180

`TapeoutConfig` 和 `TapeoutRocketConfig` 默认强制设置 `USE_SMIC180_SRAM=1`，将顶层时序存储器替换为 SMIC S018SP 宏：

```sh
make -C soc-generator SIM=vcs CONFIG=TapeoutConfig verilog
```

位于 `chipyard.mk` 默认路径的 SMIC 库提供 Tapeout 配置所使用的六种宏尺寸，以及 Pebble Buckyball 的 `32x128`、`64x128`（带 `BWEN`）。宏采用
`CLK/CEN/WEN/A/D/Q` 接口，其中 `CEN` 和 `WEN` 为低有效。`chipyard_sram_64x128` 另有低有效 `BWEN` 位写使能。`smic180_sram_sim.sources` 会展开为
对应 Verilog 模型。默认 `SMIC180_SRAM_SIM_FLAGS=+notimingcheck` 保留功能仿真并关闭库的时序
检查；时序签核应使用 SDF 或 STA。可通过 `SMIC180_SRAM_ROOT`、`SMIC180_SRAM_MDF`、
`SMIC180_SRAM_SIM_SOURCES` 与 `SMIC180_SRAM_SIM_FLAGS` 适配其他库交付版本。

一次构建只能选择一种硬 SRAM 工艺；TSMC28 流程仍可通过 `USE_TSMC28_SRAM=1` 使用。

## SMIC180 BootROM

`TapeoutConfig` 默认强制使用 S018VM 的固定 `1024x64` 宏
`S018VM_X64Y16D64_PM` 替换 BootROM，并以 `128x64`
宏 `S018VM_X8Y16D64_PM` 替换 JTAG Debug Module 的 Debug ROM。后者物理容量为
1 KiB，其中仅前 128B 是 Debug ROM 镜像，其余内容补零：

```sh
make -C soc-generator/sims/vcs CONFIG=TapeoutConfig verilog
```

ROM 宏必须预先放置在 `/data2/smic180/rom-ip/{bootrom,debugrom}`，构建只读取其中的
Verilog 模型和物理交付物，不生成或更新 ROM。可用 `SMIC180_ROM_CACHE_DIR=/path/to/rom-ip`
覆盖缓存根目录；若对应 Verilog 宏不存在，构建会直接报错。ROM 镜像、CDK、JDK 和
compiler 的变化都不会触发 ROM 生成。
Debug ROM 使用同步 64-bit 宏，并在请求后的下一个周期返回对应的 64-bit word。
非 Tapeout 配置仍可通过 `USE_SMIC180_ROM=0` 保留普通 ROM；P2E 配置会忽略该选项，始终保留普通 ROM。

## Tapeout 配置检查

选择工艺库前，先检查 `TapeoutConfig` 的实际 SRAM 规格；`mrw` 需按 `mask_gran` 分解为
独立的单端口宏：

```sh
sed -n '1,200p' \
  soc-generator/sims/vcs/generated-src/chipyard.harness.TestHarness.TapeoutConfig/\
chipyard.harness.TestHarness.TapeoutConfig.top.mems.conf
```

当前配置需要 Rocket 的 `32x21`、`512x8`、`512x32`、`512x64`、`64x21`、`64x22`，以及
Pebble scratchpad 的 `64x128`（`64x128` mrw、`mask_gran=8`，由 bit-write `BWEN` 宏承接，每 bank 一颗）和
SMatMul/Im2col 的 `32x128`。其中 64-bit masked D-cache 会分解为八个 `512x8` 宏。严格模式下，所选库的 MDF、仿真 Verilog
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
