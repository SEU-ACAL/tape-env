# Chipyard SoC 生成与仿真环境

本仓库是基于 Chipyard 的 Chisel/RISC-V SoC 生成与仿真环境。当前维护重点是
Rocket、BOOM、共享 L2、Gemmini 和 TestChipIP 的 RTL 生成，以及 Verilator/VCS
软件仿真和裸机工作负载验证。

FPGA 加速仿真及其配套编译栈不属于本仓库；FireMarshal 是独立的工作负载工具，应在
其自身工作区中使用和维护。

## 目录说明

- `soc-generator/`：SoC 生成、Verilator/VCS 仿真入口及生成的构建产物。
- `soc-generator/generator/`：Rocket、BOOM、Gemmini 和 Chipyard 集成源码。
- `applications/`：裸机测试、RISC-V 回归测试和 Zephyr 工作负载。
- `dependencies/`：非 SoC 生成器依赖，例如 DRAMSim2、CDE 和 FPGA shells。
- `.github/`：CI 工作流与回归脚本。

## 前置条件

支持的开发环境为 Linux 上的 Nix Flake。需要预先安装 Git 和启用 Flake 的 Nix；
`nix develop` 会提供 `firtool`、Verilator、SBT、Spike、RISC-V 交叉编译器及其他
必要工具。VCS 流程还需要本地安装并配置 Synopsys VCS。

## 初始化

克隆仓库后，使用仓库脚本初始化子模块：

```sh
git clone <repository-url> chipyard
cd chipyard
./init-submodules.sh
```

默认初始化 RTL 仿真所需的子模块，不初始化 Gemmini 和 Zephyr。按需使用：

```sh
./init-submodules.sh --gemmini  # Gemmini 及其 RoCC 测试工作负载
./init-submodules.sh --full     # 所有已登记子模块
```

进入开发环境：

```sh
nix develop
```

## 快速验证：运行 Hello

以下命令构建裸机 `hello.riscv`，生成 `RocketConfig` 的 Verilator 仿真器并执行它。
首次运行需要生成 RTL 和编译 Verilator C++ 模型，耗时会明显更长。

```sh
cmake -S applications/tests -B applications/tests/build -D CMAKE_BUILD_TYPE=Debug
cmake --build applications/tests/build --target hello

cd soc-generator
make CONFIG=RocketConfig run-fast \
  BINARY="$PWD/../applications/tests/build/hello.riscv"
```

成功时 UART 输出包含：

```text
Hello world from core 0, a rocket
```

日志默认位于：
`soc-generator/sims/verilator/output/chipyard.harness.TestHarness.RocketConfig/hello.log`。
使用 `run` 可同时生成指令反汇编输出；使用 `run-debug` 可生成波形和额外调试信息。

## SoC 生成与仿真

在 `nix develop` 环境中进入 `soc-generator/` 后，可使用以下入口：

```sh
make CONFIG=RocketConfig verilog
make CONFIG=RocketConfig emu
make CONFIG=RocketConfig emu-debug
make CONFIG=RocketConfig run BINARY=/absolute/path/to/program.elf
```

默认仿真器是 Verilator。VCS 可通过 `SIM=vcs` 选择，例如：

```sh
make SIM=vcs CONFIG=RocketConfig verilog
```

可用配置类可通过 `make find-configs` 查询。常用配置包括：

- `RocketConfig`：默认单核 Rocket SoC。
- `QuadChannelRocketConfig`：CI 使用的多通道 Rocket 配置。
- `MediumBoomV3CosimFastConfig`、`MediumBoomV4CosimFastConfig`：CI 使用的 BOOM 配置。
- `GemminiRocketConfig`：Gemmini 加速器配置，使用前执行 `./init-submodules.sh --gemmini`。

更多生成和仿真变量见 [soc-generator/README.md](soc-generator/README.md)。

## TapeoutConfig 与 SRAM

`verilog` 负责 Chisel/FIRRTL elaboration 和 SRAM replacement；VCS 仅编译
生成后的 Verilog。硬 SRAM 的工艺库必须与后端流片 PDK 一致，且一次只能选择一个：

- TSMC 28nm：使用 `USE_TSMC28_SRAM=1`，默认库根目录为
  `/data2/TSMC28/Memory/SRAM`。
- SMIC 180nm：使用 `USE_SMIC180_SRAM=1`，默认库根目录由
  `soc-generator/generator/chipyard/chipyard.mk` 的 `SMIC180_SRAM_ROOT` 指定。

选择 TSMC28 并生成 TapeoutConfig Verilog，再用 VCS 编译：

```sh
make -C soc-generator/sims/vcs CONFIG=TapeoutConfig USE_TSMC28_SRAM=1 verilog
make -C soc-generator/sims/vcs CONFIG=TapeoutConfig USE_TSMC28_SRAM=1
```

选择 SMIC180 时只替换工艺选择变量：

```sh
make -C soc-generator/sims/vcs CONFIG=TapeoutConfig USE_SMIC180_SRAM=1 verilog
make -C soc-generator/sims/vcs CONFIG=TapeoutConfig USE_SMIC180_SRAM=1
```

生成的 RTL 在：

```text
soc-generator/sims/vcs/generated-src/chipyard.harness.TestHarness.TapeoutConfig/gen-collateral/
```

选择工艺库前，先检查 TapeoutConfig 的实际 SRAM 规格；`mrw` 需按
`mask_gran` 分解为独立的单端口宏：

```sh
sed -n '1,200p' \
  soc-generator/sims/vcs/generated-src/chipyard.harness.TestHarness.TapeoutConfig/\
chipyard.harness.TestHarness.TapeoutConfig.top.mems.conf
```

当前配置需要 `32x21`、`512x8`、`512x32`、`512x64`、`64x21`、`64x22`
单端口宏；其中 64-bit masked D-cache 会分解为八个 `512x8` 宏。严格模式下，
所选库的 MDF、仿真 Verilog filelist 和物理交付物必须覆盖这些规格。若使用独立的
宏库交付，在命令中同时覆盖三个变量：

```sh
make -C soc-generator/sims/vcs CONFIG=TapeoutConfig USE_TSMC28_SRAM=1 \
  TSMC28_SRAM_ROOT=/path/to/sram-library \
  TSMC28_SRAM_MDF=/path/to/sram-library.mdf.json \
  TSMC28_SRAM_SIM_SOURCES=/path/to/sram-sim.sources \
  verilog
```

## 工作负载与回归

`applications/tests/` 包含常用裸机程序，例如 `hello`、`mt-hello` 和外设测试。其
构建细节见 [applications/tests/README.md](applications/tests/README.md)。Rocket/BOOM
ISA 与 benchmark 回归测试来自 `applications/riscv-tests`；构建和运行方式见
[applications/README.md](applications/README.md)。

仓库 CI 会构建 Rocket 与 BOOM 的 Verilator/VCS 回归配置，并运行 ISA、benchmark、
裸机 Hello 和 Zephyr Hello 验证。CI 使用的配置及预构建工作负载说明见
[.github/CI_README.md](.github/CI_README.md)。

## 组件来源与边界

| 组件 | 来源 | 说明 |
| --- | --- | --- |
| Rocket Chip | [SEU-ACAL/rocket-chip](https://github.com/SEU-ACAL/rocket-chip) | SoC 基础生成器 |
| BOOM | [SEU-ACAL/acal-boom](https://github.com/SEU-ACAL/acal-boom) | 高性能 RISC-V 核 |
| Inclusive Cache | [SEU-ACAL/rocket-chip-inclusive-cache](https://github.com/SEU-ACAL/rocket-chip-inclusive-cache) | 共享 L2 缓存 |
| Gemmini | [ucb-bar/gemmini](https://github.com/ucb-bar/gemmini) | 可选矩阵乘加速器 |
| TestChipIP、rocket-chip-blocks | 本仓库受控源码 | Chipyard SoC 集成模块，不作为子模块管理 |
| DRAMSim2 | `dependencies/tools/` 子模块 | 常规仿真内存模型 |
| CDE | `dependencies/tools/` 子模块 | Rocket/Chipyard 配置基础设施 |

子模块版本以 [.gitmodules](.gitmodules) 中的 URL 和父仓库记录的 gitlink 为准。修改
子模块版本时，应同时更新两者并完成对应的生成或仿真验证。

## 贡献

提交前请在 Nix 环境中运行与改动范围匹配的构建或回归测试。不要直接修改第三方子模块
工作树；需要升级时更新 `.gitmodules` 和子模块 gitlink。详细规范见
[CONTRIBUTING.md](CONTRIBUTING.md)。
