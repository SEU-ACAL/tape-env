# P2E 仿真全流程、进度汇报与网表仿真对照

## 1. 结论先行

当前工程的 P2E 顶层不是直接使用 `TapeoutConfig` 作为 Verilog 顶层，而是：

```text
HpecP2ETapeoutConfig
  └── 继承 chipyard.TapeoutConfig
      └── 生成 SoC ChipTop
          └── 由 P2ETop/HpecP2ETapeoutHarness 包装成 HPEC P2E 顶层
```

因此，`TapeoutConfig` 中的 Rocket、cache、外设地址和大部分 SoC 参数会被复用；P2E
同时替换 harness、时钟、内存通路、HTIF 和部分调试连接。

SRAM/ROM 需要区分两件事：

| 问题 | P2E 当前结论 |
| --- | --- |
| 是否复用 `TapeoutConfig` 的 SRAM/ROM 逻辑配置 | 可以，前提是配置和生成代码被继承 |
| 是否把 SMIC180/TSMC28 的 ASIC 宏原样放进 FPGA bitstream | 通常不可以 |
| 是否在 P2E 中保持相同容量、地址、初始化内容和读写协议 | 可以，使用 FPGA 可综合的 SRAM/ROM 替代模型 |
| 是否验证真实 ASIC 宏的 Liberty/SDF 延时和宏行为 | 不可以，应使用网表仿真 |

当前仓库已经明确禁止 P2E 配置启用 SMIC180 ROM 宏：`chipyard.mk` 只有在
`CONFIG= TapeoutConfig` 且显式打开 `USE_SMIC180_ROM` 时才设置
`SMIC180_ROM_ENABLED`；`HpecP2ETapeoutConfig` 会被排除。因此当前 P2E 生成的是普通
`TLROM`，而不是 `S018VM_X512Y16D64_PM`。

## 2. P2E 的完整流程

### 2.1 生成 P2E RTL

在 `tape-env` 根目录的 Nix 环境中执行：

```bash
make -C dependencies/p2e-runner/platform/tape-env verilog
```

主要产物是：

```text
dependencies/p2e-runner/platform/tape-env/generated-src/
  chipyard.p2e.hpec.P2ETop.HpecP2ETapeoutConfig/
  gen-collateral/P2ETop.sv
```

生成阶段会完成 Chisel/FIRRTL elaboration、Verilog 拆分、memory 描述处理以及默认的
P2E 片上 memory wrapper 生成。P2E 当前默认使用 `synflops` 类型的可综合 memory
模型，适合交给 FPGA 工具继续综合。

确认配置没有意外使用 ASIC ROM 宏：

```bash
rg -n 'S018VM|SMIC180|TLROM' \
  dependencies/p2e-runner/platform/tape-env/generated-src/\
  chipyard.p2e.hpec.P2ETop.HpecP2ETapeoutConfig/gen-collateral
```

正常的当前 P2E 结果应能看到 `TLROM.sv`，而不应看到由
`USE_SMIC180_ROM=1` 生成的 `S018VM_X512Y16D64_PM` BootROM 实例。

### 2.2 远端 P2E build

进入 runner 子仓库的 Nix 环境：

```bash
cd dependencies/p2e-runner
nix develop
p2e build
```

`p2e build` 会同步 runner 和 RTL 到远端，并执行：

```text
VVAC → VSYN → VCOM → FPGA PNR → RTDB 生成
```

关键产物：

```text
<remote_root>/cases/<case>/fpgaCompDir/bitstream.bit
<remote_root>/cases/<case>/fpgaCompDir/part_b0_f0/pnrDir/
<remote_root>/cases/<case>/RTDB/
```

构建进度汇报应至少记录：

| 阶段 | 说明 | 成功标志 |
| --- | --- | --- |
| PREP | 远端目录、runner、RTL、FESVR 准备 | 同步完成，依赖可用 |
| VVAC | Verilog 解析和运行时生成 | `vvacDir`、`libvCtb.so` 生成 |
| VSYN | FPGA 综合 | `xepic_vvac_top.vm` 生成 |
| VCOM | FPGA 系统编译、观测点固化 | `fpgaCompDir` 生成 |
| PNR | FPGA 布局布线和时序 | `.part_b0_f0_pnr.complete` 和 bitstream 生成 |
| RTDB | vDbg 数据库生成 | `RTDB/physical_tree.db` 或 `RTDB/xndb_tree.db` 存在 |

汇报 PNR 时应同时给出 WNS/TNS/WHS/THS 和 LUT、FF、BRAM、URAM、DSP 利用率。P2E
的时序结果是 FPGA 实现时序，不是 ASIC PVT 时序。

### 2.3 运行 workload

```bash
p2e run --image /absolute/path/to/workload.elf
```

运行阶段依次为：

1. vDbg 连接物理 FPGA。
2. 下载 bitstream。
3. 初始化 FPGA 和 DDR 校准。
4. 解析 ELF 的 `PT_LOAD` 段。
5. 通过 DDR backdoor preload 程序和可选 DTB。
6. 启动 HTIF/FESVR，向 SoC 提供 TSI 事务。
7. SoC 在 FPGA 上执行 workload。
8. FESVR 通过 `tohost/fromhost` 处理控制、输出和退出码。
9. 回传日志、退出标志和可选波形。

常用长任务命令：

```bash
p2e run --image /absolute/path/to/workload.elf --detach
p2e status
p2e fetch
p2e stop
```

结果通常回传到：

```text
waveforms/p2e/<case>/
```

其中可包含 `p2e-run.log`、`uart.log`、`vdbg.log`、`.p2e-run.exit`、
`htif_waveform.vcd/.fst` 和 PNR 报告。

### 2.4 P2E 观测与调试

观测点必须在 VCOM 阶段配置，不能对旧 bitstream 临时增加：

- `read_net`：运行时 `--get-net` 读取少量状态、握手或 PC。
- `trace_net`：`--wave` 导出物理 trace 波形。
- `write_net`：运行时写控制信号。

例如：

```bash
p2e run --image workload.elf \
  --get-net P2ETop.top.<signal>

p2e run --image workload.elf \
  --wave --wave-start 100000
```

默认 P2E bitstream 只保留少量观测信号；需要新增内部信号时，应在
`dependencies/p2e-runner/crates/p2e-runtime/src/builder/2_vcom/vcom_compile.tcl`
中加入最小集合，然后重新 `p2e build`。

## 3. TapeoutConfig 的 SRAM/ROM 替换如何映射到 P2E

### 3.1 配置继承关系

P2E 的 Scala 配置是：

```scala
class HpecP2ETapeoutConfig extends Config(
  new WithHpecP2EHTIFConsole ++
    new WithHpecP2EHarness ++
    new WithTapeoutSingleClock(5) ++
    new WithHpecP2EMemory ++
    new WithHpecP2ESerialPhy ++
    new chipyard.TapeoutConfig
)
```

所以 P2E 会继承 `TapeoutConfig` 的 cache、Rocket、外设和 BootROM 选择逻辑，但
P2E 的左侧配置会覆盖部分 harness 相关设置。特别是：

- P2E 将用户时钟配置为 5 MHz，不能直接拿 TapeoutConfig 的 100 MHz 作为 P2E
  bitstream 结论。
- P2E 使用 HPEC DDR 和 SerialTL 适配器。
- 普通 P2E harness 会 tie-off UART/JTAG；HTIF 是主要 workload 控制路径。

### 3.2 SRAM

`USE_TSMC28_SRAM=1` 或 `USE_SMIC180_SRAM=1` 的宏替换是 ASIC/工艺库相关选项。
它依赖：

- 对应工艺的 macro description file；
- 宏的 Verilog 仿真模型；
- 物理宏和工艺库；
- 与宏端口、读延时、写掩码匹配的实现。

这些宏不能直接当作 HPEC FPGA 上的物理 SRAM。P2E 可以采用以下两种方式：

**推荐方式：P2E 使用功能等价 memory。**

保持 SRAM 的深度、位宽、端口协议、读写时序和复位/初始化语义，在 P2E 生成阶段使用
`synflops`、FPGA BRAM 或 HPEC 支持的 memory primitive。这样可以验证 cache、总线和
软件行为，但不能声称验证了 ASIC SRAM 宏的 PVT 时序。

**条件方式：为 P2E 增加 FPGA 专用 wrapper。**

若必须保留统一的模块名，可以定义：

```text
ASIC flow:  wrapper → SMIC180/TSMC28 SRAM macro
P2E flow:   wrapper → FPGA-compatible RAM/synflops
GLS flow:   wrapper → ASIC behavioral SRAM model
```

三个实现必须保持相同的端口定义、读延迟、写掩码规则和初始化内容。不能把 ASIC
macro 的 `CLK/CEN/WEN/WMASK` 端口直接丢给 FPGA 工具而不提供可综合实现。

### 3.3 ROM

当前 `chipyard.mk` 对 P2E 明确屏蔽 `USE_SMIC180_ROM`，因此：

```text
TapeoutConfig + USE_SMIC180_ROM=1 → S018VM ROM
HpecP2ETapeoutConfig              → 默认 TLROM
```

这不是功能缺失，而是目标不同：P2E 需要可被 FPGA 工具处理的 ROM。若要在 P2E 中
保持 BootROM 功能，应确保：

- ROM 内容与 ASIC 版本一致；
- 地址范围和 reset vector 一致；
- 读延迟与 SoC 连接协议一致；
- P2E 使用 `TLROM` 或 FPGA ROM 实现。

如果必须观察 ASIC ROM 宏本身的初始化、时序或库模型，应转到 ASIC GLS，而不是把
`S018VM` 原宏直接塞进 P2E。

## 4. P2E 与网表仿真的分工

本工程的网表仿真由外部 `/data1/wzy/project/Tapeout-Workbench` 管理，而不是由
`tape-env/vlsi/dc` 目录管理。

### 4.1 DC 综合产物

在 `Tapeout-Workbench/2-SYN` 中运行 `run_core`。例如：

```bash
cd /data1/wzy/project/Tapeout-Workbench/2-SYN
./run_core --tech smic180 \
  --source-code-home "$TAPE_ENV/soc-generator/sims/vcs/generated-src/\
chipyard.harness.TestHarness.TapeoutConfig" \
  --filelist "$TAPE_ENV/soc-generator/sims/vcs/generated-src/\
chipyard.harness.TestHarness.TapeoutConfig/\
chipyard.harness.TestHarness.TapeoutConfig.top.f" \
  --top ChipTop \
  --sram-wrapper "$TAPE_ENV/soc-generator/sims/vcs/generated-src/\
chipyard.harness.TestHarness.TapeoutConfig/gen-collateral/\
chipyard.harness.TestHarness.TapeoutConfig.top.mems.v" \
  --clock-period 10.0 \
  --run-id <run-id>
```

对应产物位于：

```text
2-SYN/outputs/<run-id>/ChipTop.v
2-SYN/outputs/<run-id>/ChipTop.sdf
2-SYN/outputs/<run-id>/ChipTop.sdc
2-SYN/outputs/<run-id>/ChipTop.ddc
```

`run_core` 的 DC Tcl 已经执行 `write_sdf -version 2.1`，所以当前网表仿真可以做
SDF 反标；不能再把它描述成“只有 mapped.v、没有 SDF”。

### 4.2 零延时门级仿真

在 Workbench 的 `3-Pre_PR_NETSIM` 中：

```bash
cd /data1/wzy/project/Tapeout-Workbench
export TAPE_ENV=/data1/wzy/project/tape-env

make -C 3-Pre_PR_NETSIM gls_zero \
  TECH=smic180 NETLIST_RUN=<run-id>

make -C 3-Pre_PR_NETSIM run_zero \
  TECH=smic180 NETLIST_RUN=<run-id> \
  BINARY=$TAPE_ENV/applications/tests/build/hello.riscv
```

它把 DC 生成的 `ChipTop.v` 替换进 Chipyard `TestHarness`，并加载标准单元、SRAM
和必要的 ROM 行为模型。目标是检查门级连接、复位、宏接口和基本功能。

### 4.3 SDF 门级仿真

```bash
make -C 3-Pre_PR_NETSIM gls_sdf \
  TECH=smic180 NETLIST_RUN=<run-id> WAVEFORM=1

make -C 3-Pre_PR_NETSIM run_sdf \
  TECH=smic180 NETLIST_RUN=<run-id> WAVEFORM=1 \
  BINARY=$TAPE_ENV/applications/tests/build/hello.riscv
```

SDF 通过 `sdf_annotate.sv` 反标到 `TestDriver.testHarness.chiptop0`，使用匹配该
网表的标准单元和 SRAM 仿真模型。该流程可以暴露门级延时、复位释放、setup/hold
相关问题，但速度远低于 P2E。

## 5. P2E 与网表仿真的关键差异

| 维度 | P2E | Workbench 网表仿真 |
| --- | --- | --- |
| 执行平台 | 真实 HPEC FPGA | VCS 事件仿真器 |
| 输入 | P2E RTL，经过 VVAC/VSYN/VCOM/PNR | DC `ChipTop.v`，可选 `ChipTop.sdf` |
| SRAM/ROM | FPGA-compatible memory、默认 TLROM | ASIC SRAM/ROM behavioral model 和宏接口 |
| 时序含义 | FPGA PNR 后时钟和 FPGA 资源时序 | 零延时或 ASIC library + SDF 延时 |
| 速度 | 适合 Linux 和长 workload | 适合短 testcase 和门级定位 |
| 观测 | 必须提前在 VCOM 配置 `read_net/trace_net` | VCS 可生成 FSDB，内部节点更易观察 |
| 主要目标 | SoC bring-up、软件、系统级行为、FPGA 实现可行性 | ASIC 综合后连接、宏模型、复位和 SDF 时序 |
| 不能证明 | ASIC 宏 PVT、ASIC 标准单元时序 | 长时间真实硬件软件行为和 FPGA 资源可行性 |

## 6. 建议的处理策略

### 策略 A：P2E 验证系统功能

1. 使用 `HpecP2ETapeoutConfig` 生成 RTL。
2. 保持 SRAM 为 synflops/FPGA RAM，ROM 为内容一致的 `TLROM`。
3. `p2e build`，确认 VVAC、PNR、RTDB 和 bitstream 全部完成。
4. 用裸机 ELF、Linux HTIF-console ELF 运行 smoke test。
5. 用 `--get-net` 观察 PC、HTIF 握手和关键状态。

### 策略 B：网表仿真验证 ASIC IP

1. 使用 `TapeoutConfig` 生成带目标 SRAM/ROM 替换的 RTL。
2. 在 `/data1/wzy/project/Tapeout-Workbench/2-SYN` 执行 DC。
3. 检查 `ChipTop.v`、`ChipTop.sdf`、`ChipTop.sdc` 和 link library。
4. 在 `3-Pre_PR_NETSIM` 运行 `gls_zero`，先排除连接和模型问题。
5. 再运行 `gls_sdf`，检查延时、复位和宏时序。
6. 需要功耗时，在 `4-Pre_PR_STA_POWER` 使用 SDF FSDB 做 pre-layout power 估算。

### 策略 C：两条流联合回归

同一个 workload 至少记录以下信息，避免把两个流的结果混在一起：

```text
RTL/config       = HpecP2ETapeoutConfig 或 TapeoutConfig
ASIC technology  = smic180 / tsmc28
SRAM/ROM mode    = synflops、ASIC macro 或 behavioral model
P2E case         = <p2e-case>
DC run           = <run-id>
clock            = P2E FPGA clock / GLS clock period
workload ELF     = <absolute-path>
result           = exit code、UART、FSDB、PNR/STA 报告
```

## 7. 最终判断

对当前工程，最稳妥的结论是：

> `TapeoutConfig` 的 SoC 逻辑可以作为 P2E 的基础，但 ASIC SRAM/ROM 的“功能”与“物理宏”必须分开处理。P2E 使用 FPGA 可综合替代实现系统级运行；真实 SMIC180/TSMC28 宏及其 SDF 时序由 `/data1/wzy/project/Tapeout-Workbench` 的 GLS 流程验证。

只有在 HPEC 工具明确提供对应 ASIC 宏的 FPGA 映射、端口模型和综合支持时，才考虑把
宏直接引入 P2E；否则不应把 P2E bitstream 能运行误认为 ASIC 宏已经完成验证。

## 8. IP 仿真模型能否给 FPGA 综合

答案取决于模型类型，而不是文件名是否为 `.v` 或 `.sv`：

| IP 模型类型 | 能否给 P2E/FPGA 综合 | 说明 |
| --- | --- | --- |
| ASIC timing simulation model | 通常不能 | 含 `#delay`、`specify`、timing check、UDP、`initial` 初始化或厂商仿真原语 |
| ASIC functional simulation model | 通常不能直接使用 | 可能只有行为语义，包含不可综合写法或与宏端口时序不匹配 |
| synthesizable behavioral model | 可以 | 只使用可综合 RTL；最终会映射为 LUT、FF 或 FPGA BRAM |
| FPGA-specific replacement model | 可以 | 使用目标 FPGA/HPEC 支持的 RAM、ROM 或 primitive |
| black-box module declaration | 只能通过编译，不能完成实现 | 还必须提供 HPEC/FPGA 的实现 IP 或下层映射 |

### 8.1 普通仿真模型为什么不能直接综合

ASIC 仿真模型的目标是让 VCS 正确模拟宏的功能和时序，常见内容包括：

```verilog
specify
  (CLK *> Q) = (t_rise, t_fall);
endspecify

always @(posedge CLK) #0.2 Q <= mem[A];
```

`#` 延时、`specify` timing arc 和 `$width/$setuphold` 检查不是 FPGA 硬件逻辑。即使
某些工具允许跳过这些语句，剩下的模型也不一定能被 VVAC/VSYN 正确识别，或者会被
错误地综合成大量 LUT/FF。

### 8.2 推荐的统一 wrapper 方式

为同一个 IP 保持统一端口，在不同目标下选择不同实现：

```verilog
module tapeout_sram (...);
`ifdef P2E_FPGA
  // P2E: synflops、FPGA BRAM 或 HPEC memory primitive
  logic [63:0] mem [0:511];
  always_ff @(posedge clk) begin
    if (wen) mem[addr] <= wdata;
    if (ren) rdata <= mem[addr];
  end
`else
  // ASIC: SMIC180/TSMC28 hard macro 或其 GLS model
  S018SP_or_other_macro u_macro (...);
`endif
endmodule
```

实际工程中不建议简单地把完整 ASIC 仿真模型加到 P2E filelist。更安全的做法是：

1. 保留统一的 wrapper 名称和端口协议。
2. P2E 只编译 `P2E_FPGA` 分支或单独的 FPGA replacement 文件。
3. ASIC GLS 编译标准单元、SRAM/ROM behavioral model 和 SDF 分支。
4. 对比两边的读延迟、写掩码、读写冲突、复位和初始化行为。

### 8.3 SRAM 和 ROM 的具体注意点

对于 SRAM，至少要固定以下语义，否则 P2E 和 ASIC GLS 可能运行出不同结果：

- synchronous read 还是 asynchronous read；
- read-during-write 返回 old data、new data 还是 undefined；
- byte write mask 的排列顺序；
- `CEN/WEN/REN` 的有效电平；
- reset 是否清空内容；
- FPGA BRAM 的初始化方式和 ASIC 宏的上电内容。

对于 ROM，应固定：

- ROM codefile 与地址映射；
- reset vector 和容量；
- 读延迟；
- P2E 使用的 FPGA ROM 内容与 ASIC ROM 编译输入完全一致。

### 8.4 在当前 P2E 工程中的落地判断

当前 P2E runner 会收集 `rtl_dir` 下的 `.v/.sv`，再交给 VVAC/VSYN。因此，理论上可以
把一个真正可综合的 FPGA replacement model 放入生成 filelist 并参与 `p2e build`。
但当前生成结果已经使用 synflops memory wrapper，且 P2E 配置屏蔽 SMIC180 ROM 宏；
通常没有必要再把 ASIC 仿真模型塞进 P2E。

建议采用以下判断：

```text
只有 ASIC simulation model       → 留在 3-Pre_PR_NETSIM GLS
有 vendor synthesizable model    → 评估后可给 P2E，但验证资源和时序语义
有 HPEC/FPGA-specific IP model   → 可直接按 P2E wrapper 接入
没有 FPGA model                  → 使用当前 synflops/TLROM 替代
```
