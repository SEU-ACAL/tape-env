# SRAM integration

Set `USE_TSMC28_SRAM=1` when invoking a `soc-generator` target to replace top-level sequential memories with the discrete macros in `tsmc28_sram_library.mdf.json`:

```sh
make -C soc-generator SIM=vcs USE_TSMC28_SRAM=1 verilog
```

The make fragment uses `--mode strict`, so generation fails if any top-level sequential memory cannot map to a listed single-port macro. The macro library uses the TSMC `CLK/CEB/WEB/A/D/Q` interface, with active-low `CEB` and `WEB`; required `RTSEL` and `WTSEL` pins are tied to their macro-specific characterization defaults.

`tsmc28_sram_sim.sources` is expanded into a build-local filelist of the `ssg0p81v125c` TSMC timing models for VCS or Verilator. Override `TSMC28_SRAM_ROOT`, `TSMC28_SRAM_MDF`, and `TSMC28_SRAM_SIM_SOURCES` for a different installation or generated macro set.

For synthesis, add the `NLDM/*_ssg0p81v125c.lib` files of every macro reported in the generated `*.top.mems.v`. For place-and-route, add the matching `LEF/*.lef` and `GDSII/*.gds`; use the same macro module names. Do not use the simulation Verilog models as synthesis sources.

## SMIC180

Set `USE_SMIC180_SRAM=1` to replace the `TapeoutConfig` top-level sequential memories with the SMIC S018SP macros:

```sh
make -C soc-generator SIM=vcs USE_SMIC180_SRAM=1 verilog
```

The SMIC library at `/data2/smic180/SRAM/S018SP_v0p1pc_CDK/SMIC180_S018SP_v0p1c_20260722` supplies the six macro sizes used by `TapeoutConfig`. The macros use the `CLK/CEN/WEN/A/D/Q` interface; `CEN` and `WEN` are active low. `smic180_sram_sim.sources` expands into the corresponding Verilog models. The default `SMIC180_SRAM_SIM_FLAGS=+notimingcheck` preserves functional SRAM simulation while disabling the library's timing checks; use SDF or STA for timing signoff. Override `SMIC180_SRAM_ROOT`, `SMIC180_SRAM_MDF`, `SMIC180_SRAM_SIM_SOURCES`, or `SMIC180_SRAM_SIM_FLAGS` for another library delivery.

Only one hard-SRAM technology may be selected for a build. `USE_TSMC28_SRAM=1` remains available for the TSMC28 library.

For an end-to-end VCS JTAG smoke test of `TapeoutConfig` with SMIC180 SRAM
replacement, see [VCS_JTAG.md](VCS_JTAG.md).
