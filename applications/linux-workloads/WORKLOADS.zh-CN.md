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

构建器会拒绝在 `applications/linux-workloads/buildroot` 有本地修改时运行。它所需的
Buildroot 兼容调整只会写入一次性的 Git worktree，原始子仓库不会被修改。

## 移植程序

程序入口应为普通 Linux `main()`，并用 Linux 交叉编译器构建。推荐静态链接，避免
额外依赖目标 rootfs 内的共享库。

```sh
riscv64-unknown-linux-gnu-gcc -static -O2 -std=gnu11 \
  -o payload/my-workload src/main.c
```

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
`applications/scripts/build-linux-riscv-benchmarks.sh` 是参考实现：它把上游源码复制
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
约定。需要给 FireSim 构建磁盘 workload 时改为继承 `firesim-poweroff.json`，见
[README.md](README.md)。

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

## 常见问题

| 现象 | 原因与处理 |
| --- | --- |
| `Illegal instruction` 或 CSR trap | 程序仍访问特权 CSR 或使用硬件不支持的 ISA 扩展。移除它，或使用对应的 kernel driver。 |
| 程序无法执行 | 用 `riscv64-unknown-linux-gnu-gcc` 重编译；用 `file` 检查，并优先使用 `-static`。 |
| `guestmount` 或 `supermin` 失败 | 确认安装了 `libguestfs`。构建器会把 guestfs 临时文件放在 `applications/linux-workloads/build/libguestfs/`，不依赖根分区 `/tmp`。 |
| P2E 启动但看不到输出 | 配置必须继承 `htif-console.json`，并同时传入 `--dtb` 与 `--dtb-address 0x8ff00000`。 |
| rootfs 空间不足 | 在 workload JSON 中增大 `rootfs-size` 后重新构建。 |
| 提示 Buildroot 子仓库 dirty | 先处理用户已有改动；不要为了构建 workload 而 patch 子仓库。 |
