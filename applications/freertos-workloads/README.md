# FreeRTOS Workloads for TapeoutConfig

这个目录包含用于 TapeoutConfig 的 FreeRTOS workloads,可以在 P2E 上运行。

## 目录结构

```
applications/freertos-workloads/
├── freertos-kernel/          # FreeRTOS Kernel 子模块
├── CMakeLists.txt            # CMake 构建配置
├── FreeRTOSConfig.h          # FreeRTOS 配置
├── main_blinky.c             # Blinky 示例应用
├── build.sh                  # 构建脚本
├── run-p2e.sh                # P2E 运行脚本
├── README.md                 # 本文档
└── build/                    # 构建输出目录
```

## 快速开始

### 1. 初始化子模块

如果还没有初始化 FreeRTOS kernel 子模块:

```bash
cd /data1/wzy/data1-wzy/project/tape-env/applications/freertos-workloads
git submodule update --init --recursive
```

### 2. 编译 FreeRTOS Workload

```bash
cd applications/freertos-workloads
./build.sh
```

编译成功后会生成:
- `build/freertos_blinky.riscv` - FreeRTOS Blinky 示例程序
- `build/freertos_blinky.dump` - 反汇编文件

### 3. 在 P2E 上运行

#### 方法 1: 使用提供的脚本

```bash
cd applications/freertos-workloads
./run-p2e.sh freertos_blinky.riscv
```

#### 方法 2: 手动运行

```bash
cd dependencies/p2e-runner
./bin/p2e run --image /data1/wzy/data1-wzy/project/tape-env/applications/freertos-workloads/build/freertos_blinky.riscv
```

## FreeRTOS 配置说明

### TapeoutConfig 参数

- **CPU 频率**: 100 MHz (`configCPU_CLOCK_HZ`)
- **CLINT mtime 频率**: 5000 Hz (`configMTIME_CLOCK_HZ`)
- **Tick 频率**: 1000 Hz (`configTICK_RATE_HZ`)
- **堆大小**: 64 KB (`configTOTAL_HEAP_SIZE`)
- **MTIME 地址**: 0x0200bff8 (`configMTIME_BASE_ADDRESS`)
- **MTIMECMP 地址**: 0x02004000 (`configMTIMECMP_BASE_ADDRESS`)

这些配置与 TapeoutConfig 的硬件参数匹配,使用 RISC-V CLINT 作为时钟源。

### Blinky 示例

`freertos_blinky.riscv` 创建了两个任务:
- **Task 1**: 每 100ms 输出一次运行状态，共运行 10 次
- **Task 2**: 每 100ms 输出一次运行状态，共运行 10 次
- 两个任务完成后通过 `exit(0)` 自动结束 P2E workload

任务通过 HTIF printf 输出到控制台,模拟 LED 闪烁模式。

## P2E 运行流程

### 完整流程

1. **生成 RTL** (如果 Chisel/Scala 有修改):
   ```bash
   cd /data1/wzy/data1-wzy/project/tape-env
   make -C dependencies/p2e-runner/platform/tape-env verilog
   ```

2. **构建 Bitstream** (首次或 RTL 更新后):
   ```bash
   cd dependencies/p2e-runner
   nix develop
   p2e build
   ```

3. **运行 FreeRTOS Workload**:
   ```bash
   p2e run --image /data1/wzy/data1-wzy/project/tape-env/applications/freertos-workloads/build/freertos_blinky.riscv
   ```

### 运行选项

- **普通运行** (等待完成):
  ```bash
  p2e run --image <workload.riscv>
  ```

- **后台运行** (长时间任务):
  ```bash
  p2e run --image <workload.riscv> --detach
  p2e status
  p2e fetch
  ```

- **波形调试**:
  ```bash
  p2e run --image <workload.riscv> --wave --wave-start 100000
  ```

- **信号观测**:
  ```bash
  p2e run --image <workload.riscv> --get-net P2ETop.top.<signal>
  ```

## 添加新的 FreeRTOS 应用

1. 在 `applications/freertos-workloads/` 目录创建新的 `.c` 文件
2. 在 `CMakeLists.txt` 中添加编译目标:
   ```cmake
   add_executable(my_app
       my_app.c
       ${FREERTOS_SOURCES}
   )
   add_dump_target(my_app)
   ```
3. 重新编译: `./build.sh`
4. 运行: `./run-p2e.sh my_app.riscv`

## 注意事项

1. **工具链**: 需要 `riscv64-unknown-elf-gcc` 工具链
2. **架构**: 使用 `rv64imafd` (RV64GC)
3. **ABI**: `lp64d` (64位, 双精度浮点)
4. **链接脚本**: 使用 `htif.ld` (HTIF 接口)
5. **P2E 配置**: 确保 `p2e.toml` 中配置了正确的远程服务器和 FPGA 位置

## 相关文档

- FreeRTOS Kernel: https://github.com/FreeRTOS/FreeRTOS-Kernel
- P2E 运行指南: `/dependencies/p2e-runner/P2E.md`
- TapeoutConfig 定义: `/soc-generator/generator/chipyard/src/main/scala/config/TapeoutConfigs.scala`

## 故障排除

### 编译错误

如果遇到 FreeRTOS 移植相关错误,检查:
- FreeRTOS kernel 子模块是否正确初始化
- RISC-V 移植文件是否存在: `applications/freertos-kernel/portable/GCC/RISC-V/`

### P2E 运行错误

如果 P2E 运行失败:
- 检查 bitstream 是否已构建
- 验证远程服务器连接配置
- 查看日志: `waveforms/p2e/<case-name>/p2e-run.log`

### HTIF 超时

如果任务长时间运行,使用 `--continuous` 模式:
```bash
p2e run --image <workload.riscv> --continuous --continuous-poll-ms 1000
```
