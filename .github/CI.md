# Chipyard 持续集成

仓库的验证 CI 是 `Regression Tests` 工作流（`.github/workflows/regression.yml`）。它会在
目标分支为 `main` 的拉取请求中运行，也可以手动触发。

`Nightly Peripheral Regression`（`.github/workflows/nightly-peripheral-regression.yml`）每天
北京时间 00:00 运行，也可手动触发。它构建 `TapeoutConfig` VCS 仿真器，并串行执行 I2C
EEPROM 压力测试（4 轮、每轮 16 字节）、SPI Flash 压力测试（16 轮、每轮 64 字节）和
JTAG RSP 压力测试（32 步、64 次内存操作）。三项测试全部使用同一个
`TapeoutConfig`，其中 SPI Flash 和 I2C EEPROM 行为模型直接挂在该配置的 VCS harness 上。
夜间构建通过 `TAPEOUT_ENABLE_SPI_FLASH_MODEL=1` 启用 SPI 模型；普通回归不启用该模型，
因此不需要额外的 SPI Flash 镜像参数。
测试失败时会上传各测试日志和保留的 VCS 运行目录。

手动运行该工作流时，可以在 Actions 界面通过 `SPI flash regression timeout in seconds`
、`JTAG regression timeout in seconds` 和 `JTAG per-request RSP timeout in seconds`
设置超时（单位为秒，默认均为 1000）。定时运行未提供输入时也使用 1000 秒默认值。

该工作流为下列配置构建 Verilator 仿真器：

- `QuadChannelRocketConfig`
- `MediumBoomV3CosimFastConfig`
- `MediumBoomV4CosimFastConfig`

随后运行 Rocket 的 ISA、benchmark、原生 Hello 和 Zephyr Hello 回归，以及 BOOM v3/v4
的 ISA 和 benchmark 回归。BOOM 回归配置去除了 TileLink monitor；为使软件回归的耗时可接受，
其 Verilator 构建关闭断言检查。标准 BOOM 协同仿真配置仍可用于验证。Zephyr 仅覆盖
`chipyard_riscv64` 上的裸机 `samples/chipyard/hello_world`，不覆盖其他示例、SMP、网络或
Linux。构建在标记为 `builder` 的自托管运行器执行，测试在标记为 `runner` 的自托管运行器执行。

回归软件在工作流外预先构建，并由两个运行器共享：

```text
/data2/ci-workloads/
  hello.riscv
  riscv-tests/riscv64-unknown-elf/share/riscv-tests/
  zephyr/zephyr.elf
```

使用以下命令创建该目录：

```sh
nix develop --command applications/scripts/build-ci-workloads.sh
```

其中还包括 `dhrystone.riscv` 和 `fpu-stress.riscv`；后者持续执行标量 FP64 融合乘加，用于
对 FPU 敏感的功耗测量。发布端初始化固定版本的 `applications/zephyr` 子模块，通过其
`west-riscv.yml` manifest 获取固定的 Zephyr 依赖，并使用 Nix 提供的 Python、West 与
`riscv64-unknown-elf-` 工具链编译。CI 只验证每个测试用例所需的软件，不会在回归阶段编译
工作负载。生成的 Verilator 仿真器和配置专属的 `test-rules.d` 是每次 CI 运行的构建产物。

回归摘要还包含由 VCS elaboration 输出生成的 `TapeoutConfig` 地址映射。
`tapeoutconfig-regmap` 构建产物包含完整的 Markdown 寄存器字段映射、标准化 JSON、DTS、
memmap 和原始 regmap JSON 文件。

`Rocket Chip Logrotate` 用于维护回归构建产物，不执行验证；发布说明生成属于发布自动化，
也不执行 CI 验证。

## 每周综合

`Weekly Synthesis` 在每周一 Asia/Shanghai 时间 02:00（UTC 周日 18:00）运行，也可通过
GitHub Actions 手动触发。它使用 SMIC180 IO、BootROM/Debug ROM 和 SRAM 宏全替换生成
`TapeoutConfig`，并执行当前 `SEU-ACAL/Tapeout-Workbench` 的 Design Compiler 流程。

任务必须在标记为 `builder` 的自托管运行器执行，并具备 Design Compiler、VCS、PrimeTime、
Verdi 许可及该流程所需的 PDK 挂载。Design Compiler 和 PrimeTime 通过
`docker exec -i ci_env bash -lc` 在 `ci_env` 容器运行；GitHub Actions 没有 TTY，因此使用
`-i` 而不是 `-it`。为保证 IO、ROM、SRAM 全部使用物理宏，CI 仅允许 `smic180`。
SMIC180 默认时钟周期为 10.0 ns（100 MHz）。手动运行的
`Clock period in ns` 可留空以采用工艺默认值，也可通过 `CLOCK_PERIOD`（单位 ns）覆盖。

该工作流依次执行“生成 RTL 并运行 Design Compiler”和“运行 PrimeTime 功耗分析”。手动运行
可选择 `dhrystone`（默认）或 `fpu-stress` 工作负载；两者默认都使用 673046 ns 至
4470574 ns 的稳态 FSDB 窗口。PrimeTime 输出平均功耗，单位为瓦。可通过
`POWER_BENCHMARK`、`POWER_WORKLOAD`、`POWER_START_NS`、`POWER_END_NS`、
`STD_CELL_MODEL`、`STD_CELL_DB`、`SRAM_ROOT` 和 `SRAM_CORNER` 覆盖工作负载、活动窗口
与工艺路径。SMIC180 的标准单元和 SRAM 库采用相同的 SS、125C 工艺与电压角。

功耗步骤需要 PrimeTime W-2024，默认版本为 W-2024.09-SP1。结果是基于工作负载的布局前
估算，不是签核结果。任务不会上传实现文件；摘要会报告总单元面积，以及 core、JTAG 和
Serial-TL 三个时钟组内 I2R/R2R/R2O/I2O 路径的最差建立时间裕量。它还会按宏类型和 MDF
端口族（例如 `1rw`）统计硬 SRAM 实例数，并报告 PrimeTime 的内部、开关、漏电和总功耗。
