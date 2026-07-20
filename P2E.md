# Tapeout P2E 集成

完整的 HPEC P2E 使用说明由子仓库维护，见
[dependencies/p2e-runner/P2E.md](dependencies/p2e-runner/P2E.md)。其中包括 SSH/密码
配置、远端从零构建、HTIF ELF 运行、DDR preload、波形调试、PNR 时序和 FPGA 资源报告。

本文件只记录 Tapeout 工程专属的生成入口。所有命令从仓库根目录执行：

```sh
cp p2e.toml.example p2e.toml
# Edit p2e.toml: set the SSH host and remote_root for this user.
nix develop
make -C dependencies/fpga SUB_PROJECT=hpec-p2e verilog
p2e build
p2e run --image /path/to/workload.elf
```

`make` 成功后，`p2e.toml` 指定的 RTL 目录应包含：

```text
dependencies/fpga/generated-src/chipyard.p2e.hpec.P2ETop.HpecP2ETapeoutConfig/gen-collateral/P2ETop.sv
```

根目录的 `p2e.toml` 从模板创建后只保存本工程的非敏感默认值，例如 RTL 目录、SSH
别名和远端工作目录；它被 Git 忽略。密码必须通过 `p2e configure-password` 写入
`.p2e/hpec-p2e.password`，不要加入 `p2e.toml` 或提交到仓库。

`p2e` 命令会自动进入 `dependencies/p2e-runner` 的 Nix 开发环境；Cargo、Rust、SSH、
rsync 和 sshpass 不由父仓库的 `flake.nix` 提供。父仓库的 `nix develop` 仍用于 Chisel
RTL 生成。
