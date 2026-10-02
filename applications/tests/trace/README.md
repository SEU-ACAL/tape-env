# Trace 测试

本目录集中维护 PULP `rv_tracer` 测试程序，以及可复现的 Tapeout 验证流程。

## 测试程序

- `trace_test.c`：通用指令和控制流测试
- `test_address_fixed.c`：互补的指令地址范围过滤测试
- `test_exception_fixed.c`：异常原因过滤寄存器配置测试
- `test_privilege_fixed.c`：特权级过滤寄存器配置测试
- `test_lossy_fixed.c`：有损传输压力测试
- `test_exception_filter_real.c`、`test_tval_range_real.c`：CAUSE/TVAL/TVEC 过滤测试
- `test_iaddr_filter_real.c`：指令地址和组合特权过滤测试
- `test_privilege_filter_real.c`、`test_privilege_exception.c`：特权级和异常测试
- `test_lossless_minimal.c`：确定性 lossless 压力测试
- `test_shallow_toggle.c`：SHALLOW_TRACE 探针测试

在仓库根目录使用 Nix 环境构建：

```bash
nix develop .#default --command bash -c \
  'cmake --build applications/tests/build --target trace_test test_address_fixed test_exception_fixed test_privilege_fixed test_lossy_fixed -j$(nproc)'
```

## 地址过滤采集

```bash
./applications/tests/trace/run_address_filter.sh
```

结果写入 `trace_verification/result/`。脚本会分别保存以下产物：

- SPI 原始 nibble 流
- 原始 E-Trace packet 解码
- 基于 ELF 重建的指令 trace
- RTL `PULP_FILTER_ACCEPT` 实际接受的指令 trace

## SPI tracer CI

夜间外设 CI 使用 `applications/tests/ci-spi-trace-test.sh`，在独立目录构建并执行
7 个 IADDR/特权/异常用例。脚本支持 `TapeoutConfig` 和 `TapeoutRocketConfig`
仿真器，构建时须关闭 SPI Flash 模型（`TAPEOUT_ENABLE_SPI_FLASH_MODEL=0`）。
异常用例使用 `test_privilege_exception_trace`：仅匹配 U-mode，保留 ECALL 前的
同步起点，解码后检查 cause=8；原 `test_privilege_exception` 仍启用 cause 等值过滤。

```bash
nix develop .#default --command env \
  SIMV="$PWD/soc-generator/sims/vcs/simv-chipyard.harness-TapeoutRocketConfig" \
  SPI_TRACE_RESULT_DIR="$PWD/trace_verification/result/spi_ci_latest" \
  SPI_TRACE_CI_TIMEOUT=1000 bash applications/tests/ci-spi-trace-test.sh
```

`SPI_TRACE_CI_TIMEOUT` 是每个 workload 的仿真超时（秒）。`SPI_TRACE_RESULT_DIR`
省略时使用临时目录，成功后清理，失败时保留；指定时保留 SPI 流和各阶段日志。
`check_spi_trace.py` 校验解码返回码、完整帧、ELF 指令地址及特权/异常信息，任一
用例失败都会使 CI 返回非零。检查器自身的回归测试可用以下命令运行：

```bash
python3 -m unittest discover -s applications/tests/trace -p 'test_check_spi_trace.py'
```

## Tapeout 全量回归

`run_trace_regression.sh` 从任意当前目录定位仓库根目录，依次运行 18 个
固定 `NO_TIME=1`、`NO_CONTEXT=1` profile 的 VCS 仿真、SPI 解帧和
`pulp_chipyard` 重建。两个 legacy APB 地址读回均为 `1`，写入会被忽略。
运行前必须使用 `VCS_FORCE_FULL=1` 重建 `TapeoutRocketConfig`，避免复用旧
`simv`：

```bash
nix develop .#default --command bash -lc \
  'make -B -C soc-generator/sims/vcs SIM=vcs \
   CONFIG=TapeoutRocketConfig VCS_FORCE_FULL=1'

./applications/tests/trace/run_trace_regression.sh
```

结果默认写入 `trace_verification/result/tapeout_*_latest/`，汇总写入
`trace_verification/final_trace_regression_summary.txt`。可通过
`TRACE_REGRESSION_OUT` 和 `TRACE_REGRESSION_SUMMARY` 覆盖输出路径。

每个用例必须同时检查 `sim.rc`、`deframe.rc`、`decode.rc` 和 decoder 语义。
过滤后零指令的排除用例返回 decoder code `2`，属于预期结果；不能仅凭
仿真返回码 `0` 宣称功能正确。time/context packet 不属于此硬件 profile；
中断仍不在该脚本范围内。
