# TapeoutConfig VCS JTAG 冒烟测试

[English version](VCS_JTAG.md)

本文用于验证替换 SMIC180 硬 SRAM 后，VCS `TapeoutConfig` 仿真器的 JTAG 调试链路。
它覆盖从主机到 DUT 的完整通路，但不验证 SRAM 时序：

```text
VCS 仿真器 -> SimJTAG Remote Bitbang -> OpenOCD -> GDB
```

该冒烟测试会暂停 hart、读取程序计数器、写入并读回 `a0`，最后通过 Debug Module
的系统总线访问（SBA）写入并读回 DRAM 字。它不覆盖 `resume`/再次 `halt`、单步或硬件断点。

## 前置条件

- JTAG 工作负载已放在 `applications/tests/jtag`，本测试不再依赖 P2E 子模块。

- 使用正常开发 shell 构建和运行 VCS：

  ```sh
  nix develop
  ```

  该 shell 会配置 VCS ABI（`VCS_ARCH_OVERRIDE=linux` 和
  `EXTRA_SIM_LDFLAGS=-no-pie`）。保持 shell 默认的 `RISCV` 工具链，不能用独立、
  更新的 Spike 包覆盖它。链接到较新 `libstdc++` 的工具可能与 VCS 的 GCC 11 链接环境不兼容。

- SMIC180 SRAM PDK 必须位于 `chipyard.mk` 中的默认位置；若本机位置不同，需要将
  `SMIC180_SRAM_ROOT` 指向实际的 PDK 交付目录。

## 构建工作负载和仿真器

在仓库根目录、正常开发 shell 中执行：

```sh
make -C applications/tests/jtag

make -C soc-generator \
  SIM=vcs \
  CONFIG=TapeoutConfig \
  USE_SMIC180_SRAM=1 \
  emu
```

`USE_SMIC180_SRAM=1` 会以严格模式选择 `smic180_sram_library.mdf.json`，并将
SMIC SRAM Verilog 模型加入 VCS 文件列表。生成的仿真器路径为：

```text
soc-generator/sims/vcs/simv-chipyard.harness-TapeoutConfig
```

若修改了 `remote_bitbang.cc`，测试前必须强制重建仿真器：

```sh
make -C soc-generator \
  SIM=vcs \
  CONFIG=TapeoutConfig \
  USE_SMIC180_SRAM=1 \
  clean-sim
make -C soc-generator \
  SIM=vcs \
  CONFIG=TapeoutConfig \
  USE_SMIC180_SRAM=1 \
  emu
```

## 启动 VCS

保持正常开发 shell 打开，在仓库根目录执行下列命令。`+jtag_rbb_enable=1` 会启用
`SimJTAG`；仿真器会将动态分配的 Remote Bitbang 端口写到 stderr，并等待客户端连接。

```sh
simv=$PWD/soc-generator/sims/vcs/simv-chipyard.harness-TapeoutConfig
elf=$PWD/applications/tests/jtag/build/gdb-loop.elf
dram_ini=$PWD/soc-generator/generator/testchipip/src/main/resources/dramsim2_ini

"$simv" \
  +permissive \
  +dramsim \
  +dramsim_ini_dir="$dram_ini" \
  +max-cycles=0 \
  +notimingcheck \
  +jtag_rbb_enable=1 \
  +permissive-off \
  "$elf" \
  2>sim-jtag.stderr | tee sim-jtag.stdout
```

Remote Bitbang 端口是临时端口，不得写死。下文刻意使用 OpenOCD GDB 端口 `3335`，
从而不影响用户可能已在 `3333` 启动的服务。

## 启动 OpenOCD

在第二个终端进入轻量调试 shell 后启动 OpenOCD。仍需在仓库根目录执行，保证下一节的
ELF 路径不变。

```sh
nix develop .#jtag-debug

rbb_port=$(sed -n 's/.*Listening on port \([0-9][0-9]*\).*/\1/p' sim-jtag.stderr | tail -n 1)
[ -n "$rbb_port" ] || { echo 'Remote Bitbang port is not ready'; exit 1; }

export REMOTE_BITBANG_HOST=127.0.0.1
export REMOTE_BITBANG_PORT="$rbb_port"

openocd \
  -c 'adapter driver remote_bitbang' \
  -c 'remote_bitbang host $::env(REMOTE_BITBANG_HOST)' \
  -c 'remote_bitbang port $::env(REMOTE_BITBANG_PORT)' \
  -c 'transport select jtag' \
  -c 'bindto 127.0.0.1' \
  -c 'gdb_port 3335' \
  -c 'telnet_port disabled' \
  -c 'tcl_port disabled' \
  -c 'set _CHIPNAME riscv' \
  -c 'jtag newtap $_CHIPNAME cpu -irlen 5' \
  -c 'set _TARGETNAME $_CHIPNAME.cpu' \
  -c 'target create $_TARGETNAME riscv -chain-position $_TARGETNAME' \
  -c 'reset_config none' \
  -c 'riscv set_reset_timeout_sec 30' \
  -c 'riscv set_command_timeout_sec 30' \
  -c 'init'
```

初始化成功时，OpenOCD 日志应包含：

```text
JTAG tap: riscv.cpu tap/device found: 0x00000001
datacount=8 progbufsize=16
Examined RISC-V core; found 1 harts
hart 0: XLEN=64
Listening on port 3335 for gdb connections
```

`0x00000001` 是该仿真 TAP 的预期 ID，不是量产芯片的厂商 ID。

## 运行 GDB 冒烟测试

在第三个终端运行，或将 OpenOCD 放到后台后在第二个终端继续运行。使用相同的调试 shell。
下列定向命令会让目标最终保持暂停状态。

```sh
elf=$PWD/applications/tests/jtag/build/gdb-loop.elf

riscv64-unknown-elf-gdb -batch \
  -ex 'set pagination off' \
  -ex 'set confirm off' \
  -ex 'set remotetimeout 30' \
  -ex "file $elf" \
  -ex 'target extended-remote :3335' \
  -ex 'monitor halt' \
  -ex 'printf "JTAG_PC="' \
  -ex 'print/x $pc' \
  -ex 'set $a0 = 0x1234abcd' \
  -ex 'printf "JTAG_A0="' \
  -ex 'print/x $a0' \
  -ex 'set {unsigned int}0x80100000 = 0x4a544147' \
  -ex 'printf "JTAG_MEM="' \
  -ex 'x/wx 0x80100000' \
  -ex 'disconnect' \
  -ex 'quit'
```

预期输出类似：

```text
JTAG_PC=$1 = 0x80000042
JTAG_A0=$2 = 0x1234abcd
JTAG_MEM=0x80100000:  0x4a544147
```

由于 halt 请求到达时 JTAG 工作负载仍在执行，PC 的具体值可能不同。`a0` 和内存的读回值必须
与上述数值完全一致。

## 通过标准和清理

以下条件必须全部满足，测试才通过：

1. OpenOCD 报告 TAP ID、DTM 参数和一个 RV64 hart。
2. `monitor halt` 成功，且 GDB 可以读取 `$pc`。
3. 写入后 `$a0` 读回 `0x1234abcd`。
4. 通过 SBA 写入后，`0x80100000` 读回 `0x4a544147`。

用 `disconnect` 和 `quit` 退出 GDB，再用 `Ctrl-C` 停止 OpenOCD，最后用 `Ctrl-C` 停止
VCS。若冒烟测试已经通过、之后才终止仿真器，OpenOCD 在退出时可能报告 Remote Bitbang
socket reset；这是正常的清理日志。

## 当前限制

- `resume` 后再次 `halt` 尚未在 VCS 中建立为稳定的测试用例。
- 硬件断点和 `stepi` 不属于该冒烟测试。Debug Module 只暴露一个 trigger，OpenOCD 可能报告
  重复的断点地址。
- `+notimingcheck` 适用于硬 SRAM 替换后的功能仿真，不是 SRAM 时序签核流程。
