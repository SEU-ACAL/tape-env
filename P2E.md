# Tapeout P2E 集成

完整的 HPEC P2E 使用说明由子仓库维护，见
[dependencies/p2e-runner/P2E.md](dependencies/p2e-runner/P2E.md)。其中包括 SSH/密码
配置、远端从零构建、HTIF ELF 运行、DDR preload、波形调试、PNR 时序和 FPGA 资源报告。

本文件只记录 Tapeout 工程专属的生成入口。先在仓库根目录生成 RTL，再进入
`p2e-runner` 子仓库运行 P2E：

```sh
cp p2e.toml.example p2e.toml
# Edit p2e.toml: set the SSH host and remote_root for this user.
nix develop
make -C dependencies/p2e-runner/platform/tape-env verilog

cd dependencies/p2e-runner
nix develop
p2e build
p2e run --image /path/to/workload.elf
```

`make` 成功后，`p2e.toml` 指定的 RTL 目录应包含：

```text
dependencies/p2e-runner/platform/tape-env/generated-src/chipyard.p2e.hpec.P2ETop.HpecP2ETapeoutConfig/gen-collateral/P2ETop.sv
```

根目录的 `p2e.toml` 从模板创建后只保存本工程的非敏感默认值，例如 RTL 目录、SSH
别名和远端工作目录；它被 Git 忽略。密码必须通过 `p2e configure-password` 写入
`.p2e/hpec-p2e.password`，不要加入 `p2e.toml` 或提交到仓库。

`p2e` 命令和对应的 Cargo、Rust、SSH、rsync、sshpass 环境均由
`dependencies/p2e-runner` 管理；父仓库的 `nix develop` 仅用于 Chisel RTL 生成。

Linux 在当前 HPEC wrapper 中的物理 UART TX 没有连接至宿主机。需要观察 Linux
bring-up 时，使用 `applications/scripts/build-linux-workload.sh --htif-console` 生成
HTIF-console ELF 和 DTB，再按 [applications/linux-workloads/README.md](applications/linux-workloads/README.md)
的 `p2e run --dtb ... --dtb-address 0x8ff00000` 命令运行。该调试模式不替代默认 UART
配置。
