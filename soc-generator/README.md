# soc-generator

`soc-generator` is the SoC generation and simulation top-level.

Primary entry points:

- `make CONFIG=RocketConfig verilog`
- `make CONFIG=RocketConfig emu`
- `make CONFIG=RocketConfig emu-debug`
- `make CONFIG=RocketConfig run BINARY=/abs/path/test.elf`

Enter the repository Nix environment before running these commands:

```sh
nix develop
cd soc-generator
```

By default these commands use `sims/verilator`. Set `SIM=vcs` to use the VCS
entry point:

```sh
make SIM=vcs CONFIG=RocketConfig verilog
```

`generator/` contains the SoC generator sources and submodules. Non-generator
dependencies are stored in the sibling `../dependencies`. `soc-generator`
intentionally does not contain a `dependencies/` entry; the SBT build is loaded
from the repository root so `soc-generator/generator` and `dependencies` are
both inside the build root.

Application and software trees live at the repository top level under
`../applications`.

## Application boundary

`soc-generator` does not build application binaries. Build the RISC-V application in
`../applications` (or another application workspace) first, then pass its existing ELF
to the simulator:

```sh
make CONFIG=RocketConfig run BINARY=/abs/path/test.elf
```

The `run` target validates that `BINARY` already exists and uses it only as a
simulation input.
