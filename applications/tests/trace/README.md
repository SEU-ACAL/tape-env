# Trace 测试

本目录集中维护 PULP `rv_tracer` 测试程序，以及可复现的地址过滤采集流程。

## 测试程序

- `trace_test.c`：通用指令和控制流测试
- `test_address_fixed.c`：互补的指令地址范围过滤测试
- `test_exception_fixed.c`：异常原因过滤寄存器配置测试
- `test_privilege_fixed.c`：特权级过滤寄存器配置测试
- `test_lossy_fixed.c`：有损传输压力测试

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
