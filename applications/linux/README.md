# FireMarshal Linux 工作负载

此目录存放 Tapeout 使用的 FireMarshal workload 配置。默认的
`workloads/poweroff.json` 以 FireMarshal 的 Chipyard `br-base` 为基础，构建
Buildroot Linux、OpenSBI 和根文件系统。

当前 P2E harness 没有 FireMarshal 的块设备接口，因此默认命令使用
`--no-disk`，把根文件系统放入 initramfs，生成一个可由 P2E DDR preload 载入的
ELF：

```sh
cd /path/to/tape-env
nix develop --command applications/scripts/build-linux-workload.sh
```

首次运行会初始化 FireMarshal 的 Linux、OpenSBI、Buildroot 和 BusyBox 子模块；随后
会下载或构建 Buildroot，耗时和磁盘占用都明显高于裸机 workload。构建产物默认写入
`applications/linux/build/`，不会写入 Git 跟踪文件：

```text
applications/linux/build/chipyard/tape-env-linux-poweroff/
  tape-env-linux-poweroff-bin-nodisk  # P2E 使用的 OpenSBI + Linux ELF
  tape-env-linux-poweroff-bin-nodisk-dwarf
  tape-env-linux-poweroff.img         # 生成 initramfs 时的中间 rootfs
  linux_config
  buildroot_config
```

构建后的 P2E 调用从 runner 子仓库执行：

```sh
cd /path/to/tape-env/dependencies/p2e-runner
nix develop
p2e run --image \
  ../../applications/linux/build/chipyard/tape-env-linux-poweroff/tape-env-linux-poweroff-bin-nodisk
```

`--disk` 可生成标准 FireMarshal boot ELF 和 ext2 根文件系统镜像，适用于后续有块设备的
QEMU/FireSim 平台；当前 P2E 不能挂载该 `.img`，不要把 disk 模式的 ELF 用于 P2E。
自定义 workload 时复制 `workloads/poweroff.json`，并通过
`--config /absolute/or/repository-relative/path.json` 指定。也可使用
`--output /path/to/artifacts` 隔离不同实验的生成结果。

FireMarshal 在无 disk 模式下仍需用 `guestmount` 读取 rootfs 以生成 initramfs；主机需要
安装 `libguestfs` 提供的 `guestmount` 命令。Nix development shell 提供 FireMarshal 所需
Python 依赖和 Linux RISC-V 交叉编译器。
