# 构建 Linux Workload

本文说明如何把一个 C/C++ 程序、bare-metal 测试，或一组已有可执行文件移植为
Tapeout/P2E 可运行的 Linux 用户态 workload。

P2E 没有 Linux 块设备。构建流程会把 workload 文件放入 Buildroot rootfs，再将
rootfs 作为 initramfs 嵌入启动 ELF。因此不能把 bare-metal ELF 直接塞进 Linux
镜像；程序本身必须按 RISC-V Linux ABI 重新编译。

## 前置条件

克隆后初始化一次 Linux 依赖：

```sh
./init-submodules.sh --linux
```

无磁盘镜像构建依赖 `libguestfs` 提供的 `guestmount`。在 FireMarshal 开发环境中
构建：

```sh
nix develop .#firemarshal
```

Buildroot 2024.05 的外部工具链版本选择器最高到 GCC 14。FireMarshal 的 Nix wrapper
实际使用当前 GCC 15，但仅在 Buildroot 和 FireMarshal 的版本探测中报告 GCC 14.3；GCC
15 满足 GCC 14 的功能下限。若要替换为其他编译器，必须先升级 Buildroot 或同步更新该
兼容边界。

构建器会拒绝在 `applications/linux-workloads/buildroot` 有本地修改时运行。它不会给
Buildroot 打补丁；一次性的 Git worktree 承载未修改的源码，生成文件只写到被忽略的
`output/` 路径。Buildroot 1.34 的 `fakeroot` 可执行文件也只在该 `output/` 目录中被
替换为 Nix 提供的 `fakeroot`，小型 host `makedevs` 工具也只在这里按同一 Nix 闭包
重建，以生成 initramfs；Buildroot 源码和 Makefile 均不变。

## 移植程序

程序入口应为普通 Linux `main()`，并用 Linux 交叉编译器构建。推荐静态链接，避免
额外依赖目标 rootfs 内的共享库。

`build-linux-workload.sh` 不编译 C/C++ 源码；它只将 workload JSON 的 `files` 中已经
生成的文件复制到 guest rootfs，再把 rootfs 打包进启动 ELF。也就是说，下面的交叉编译
命令才是把你的源码变成 Linux workload 的步骤，随后才执行镜像打包。

```sh
riscv64-unknown-linux-gnu-gcc -static -O2 -std=gnu11 \
  -o payload/my-workload src/main.c
```

这里的 `payload/` 是你在 workload 源码目录中自行创建的目录。它作为 JSON `files`
映射的输入被复制到 guest rootfs，并不是构建生成的 OpenSBI 或 P2E payload 文件。最终
可供 P2E 加载的产物是 workload 构建目录中的 `*-bin-nodisk` ELF。

Make 工程可使用等价设置：

```make
CC := riscv64-unknown-linux-gnu-gcc
CFLAGS += -O2
LDFLAGS += -static
```

已有 bare-metal workload 通常需要做以下替换：

| bare-metal 依赖 | Linux 用户态替换方式 |
| --- | --- |
| `crt.S`、`test.ld`、`-nostdlib`、`tohost` | 使用正常 C runtime，在 `main()` 中返回状态码 |
| `syscalls.c`、半主机输出 | libc 的 `printf`、文件操作和 POSIX syscall |
| `setStats`、`mcycle`、`minstret` | `clock_gettime(CLOCK_MONOTONIC, ...)` 或 Linux perf 接口 |
| M-mode CSR、PMP、直接 MMIO 特权访问 | 删除、模拟，或移至 kernel driver；用户态不能直接使用 |
| bare-metal hart 启动和 barrier | 单进程执行；需要并发时使用 `pthread` |

若目标是功能等价，保持原有数据集头文件和循环边界不变。当前的
`applications/linux-workloads/examples/riscv-benchmarks/build.sh` 是参考实现：它把上游源码复制
到临时目录，只替换运行时层，不修改 `riscv-tests` 子仓库。

打包前先检查生成的 ELF：

```sh
file payload/my-workload
qemu-riscv64 payload/my-workload
```

`qemu-riscv64` 是可选的宿主机 smoke test；P2E 才是硬件验证。

## 组织 Payload

使用一个会整体复制到 guest 的目录。对于多个可执行文件，推荐用 shell 脚本顺序
启动并输出可解析的结果标记。

```text
applications/my-workload/
  src/main.c
  payload/
    my-workload
    run.sh
```

例如 `payload/run.sh`：

```sh
#!/bin/sh
set -eu

cd "$(dirname "$0")"
./my-workload
printf 'MY_WORKLOAD_RESULT status=PASS\n'
```

脚本需要带可执行权限。命令返回非零会使 Linux workload 失败，并通过 HTIF 传递给
P2E。

## 新建 Workload 配置

创建 `applications/linux-workloads/workloads/my-workload.json`：

```json
{
  "name": "tape-env-linux-my-workload",
  "base": "htif-console.json",
  "workdir": "../..",
  "files": [
    ["my-workload/payload", "/opt/my-workload"]
  ],
  "command": "/opt/my-workload/run.sh"
}
```

`workdir` 相对于 JSON 文件所在目录。上例中的 `../..` 从
`applications/linux-workloads/workloads/` 解析到 `applications/`，因此 payload 源路径为
`applications/my-workload/payload`。

`files` 的每一项格式是 `[宿主机源路径, guest 目标路径]`，目录会递归复制。
`command` 会在 Linux 启动完成后由 guest init 脚本执行。

P2E workload 必须继承 `htif-console.json`，以提供 HTIF console 和 OpenSBI 的 DTB
约定。

## 构建 P2E 镜像

构建自定义配置并启用 HTIF：

```sh
nix develop .#firemarshal --command \
  applications/scripts/build-linux-workload.sh \
  --config applications/linux-workloads/workloads/my-workload.json \
  --htif-console
```

关键产物如下：

```text
applications/linux-workloads/build/tape-env/tape-env-linux-my-workload/
  tape-env-linux-my-workload-bin-nodisk
  tape-env-linux-my-workload.img

applications/linux-workloads/build/tape-env/tape-env-linux-htif-console/
  tape-env-linux-htif-console.dtb
```

`.img` 可用于检查 guest 文件；`*-bin-nodisk` ELF 是 P2E 输入。`--htif-console` 会生成
所有继承 HTIF console base 的 workload 共用的 DTB。

## 在 P2E 上运行

使用一个已经成功构建的 P2E bitstream case。下面命令只执行 `p2e run`，不会构建
bitstream：

```sh
./dependencies/p2e-runner/bin/p2e run \
  --image "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-my-workload/tape-env-linux-my-workload-bin-nodisk" \
  --dtb "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-htif-console/tape-env-linux-htif-console.dtb" \
  --dtb-address 0x8ff00000 \
  --detach
```

长时间 workload 可在不打断 FPGA 的情况下查询和拉取日志：

```sh
./dependencies/p2e-runner/bin/p2e status
./dependencies/p2e-runner/bin/p2e fetch
```

下载的 `p2e-run.log` 包含 Linux 启动日志、workload stdout、HTIF 返回码，以及 `run.sh`
打印的结果标记。成功运行应同时出现预期的应用结果和
`P2E HTIF completed with exit code 0`。

## 完整示例：编译自己的 C Workload 并在 P2E 运行

以下示例假定你的 Linux 用户态源码入口是
`applications/my-workload/src/main.c`，并且其中使用普通的 `main()`。所有命令均从仓库根
目录执行。

首次使用仓库时初始化 Linux 子仓库：

```sh
./init-submodules.sh --linux
```

创建用于放入 guest 的目录，并将源码交叉编译为静态 RISC-V Linux ELF。多源文件、头文件
目录和库可以继续追加到同一条 `gcc` 命令：

```sh
mkdir -p applications/my-workload/payload

nix develop .#firemarshal --command \
  riscv64-unknown-linux-gnu-gcc -static -O2 -std=gnu11 \
  -o applications/my-workload/payload/my-workload \
  applications/my-workload/src/main.c
```

创建 `applications/my-workload/payload/run.sh`，用于固定 guest 内工作目录、运行程序并打印
结果标记：

```sh
#!/bin/sh
set -eu

cd "$(dirname "$0")"
./my-workload
printf 'MY_WORKLOAD_RESULT status=PASS\n'
```

赋予脚本可执行权限：

```sh
chmod 0755 applications/my-workload/payload/run.sh
```

然后创建 `applications/linux-workloads/workloads/my-workload.json`：

```json
{
  "name": "tape-env-linux-my-workload",
  "base": "htif-console.json",
  "workdir": "../..",
  "files": [
    ["my-workload/payload", "/opt/my-workload"]
  ],
  "command": "/opt/my-workload/run.sh"
}
```

这里 `workdir` 使 `my-workload/payload` 解析为宿主机目录
`applications/my-workload/payload`；`files` 复制的是编译完成的 ELF 和 `run.sh`，不是 C 源码。
用该 JSON 打包 P2E 无磁盘镜像和 DTB：

```sh
nix develop .#firemarshal --command \
  applications/scripts/build-linux-workload.sh \
  --config applications/linux-workloads/workloads/my-workload.json \
  --htif-console \
  --jobs 16
```

最后复用已有的成功 P2E bitstream case 运行，不执行 `p2e build`：

```sh
./dependencies/p2e-runner/bin/p2e run \
  --image "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-my-workload/tape-env-linux-my-workload-bin-nodisk" \
  --dtb "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-htif-console/tape-env-linux-htif-console.dtb" \
  --dtb-address 0x8ff00000 \
  --detach

./dependencies/p2e-runner/bin/p2e status
./dependencies/p2e-runner/bin/p2e fetch
```

从 `p2e-run.log` 确认 `MY_WORKLOAD_RESULT status=PASS` 和
`P2E HTIF completed with exit code 0`。这就是普通 workload 的完整流程；下面的
benchmark 示例仅是其中“交叉编译”步骤由专用脚本代替。

## 完整示例：Linux RISC-V Benchmark 到 P2E

以下是在仓库根目录执行的完整流程。它构建 CI 使用的 RISC-V benchmark Linux 移植版，
打包为 P2E 无磁盘 ELF，再在一个已有的成功 P2E bitstream case 上运行。全程不执行
`p2e build`，不会重新构建 bitstream。

首次使用仓库时先初始化 Linux 子仓库：

```sh
./init-submodules.sh --linux
```

先构建 benchmark。该命令生成 11 个静态 Linux RISC-V 可执行文件和 suite runner：

```sh
nix develop .#firemarshal --command \
  applications/linux-workloads/examples/riscv-benchmarks/build.sh
```

该脚本默认写入 `applications/linux-workloads/examples/riscv-benchmarks/build/`，并拒绝覆盖已有目录。若该目录
已经是所需版本，可跳过这一步，直接打包；若修改 benchmark 后需要重新编译，使用新的
`--output` 目录，并在一份新的 workload JSON 中把 `files` 源路径同步改为该目录。

用 16 个并行任务构建 P2E Linux 镜像和 HTIF DTB：

```sh
nix develop .#firemarshal --command \
  applications/scripts/build-linux-workload.sh \
  --config applications/linux-workloads/workloads/riscv-benchmarks.json \
  --htif-console \
  --jobs 16
```

随后复用最新的成功 P2E case 运行镜像。`--detach` 让终端立即返回，适合 Linux workload：

```sh
./dependencies/p2e-runner/bin/p2e run \
  --image "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-riscv-benchmarks/tape-env-linux-riscv-benchmarks-bin-nodisk" \
  --dtb "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-htif-console/tape-env-linux-htif-console.dtb" \
  --dtb-address 0x8ff00000 \
  --detach

./dependencies/p2e-runner/bin/p2e status
./dependencies/p2e-runner/bin/p2e fetch
```

最终 P2E 输入是
`applications/linux-workloads/build/tape-env/tape-env-linux-riscv-benchmarks/tape-env-linux-riscv-benchmarks-bin-nodisk`；
`.img` 只是用于检查 rootfs。下载的 `p2e-run.log` 应显示 11 个 benchmark 都执行完成，
`pmp` 因需要 M-mode PMP CSR 而预期跳过，并以 `P2E HTIF completed with exit code 0` 结束。

## 常见问题

| 现象 | 原因与处理 |
| --- | --- |
| `Illegal instruction` 或 CSR trap | 程序仍访问特权 CSR 或使用硬件不支持的 ISA 扩展。移除它，或使用对应的 kernel driver。 |
| 程序无法执行 | 用 `riscv64-unknown-linux-gnu-gcc` 重编译；用 `file` 检查，并优先使用 `-static`。 |
| `guestmount` 或 `supermin` 失败 | 确认安装了 `libguestfs`。构建器会把 guestfs 临时文件放在 `applications/linux-workloads/build/libguestfs/`，不依赖根分区 `/tmp`。 |
| P2E 启动但看不到输出 | 配置必须继承 `htif-console.json`，并同时传入 `--dtb` 与 `--dtb-address 0x8ff00000`。 |
| rootfs 空间不足 | 在 workload JSON 中增大 `rootfs-size` 后重新构建。 |
| 提示 Buildroot 子仓库 dirty | 先处理用户已有改动；不要为了构建 workload 而 patch 子仓库。 |
