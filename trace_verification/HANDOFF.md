# PULP rv_tracer Verification Handoff

## 中文交接摘要

截至 2026-09-12，`TapeoutRocketConfig` 已完成多次 `VCS_FORCE_FULL=1` 强制全量
构建，并按 **VCS → SPI deframe → `pulp_chipyard` decoder** 链路复跑 18 项
TVAL/CAUSE/TVEC/IADDR/Privilege/`mret` 回归；包含用例均通过，完全排除用例的
decoder 返回码 `2` 属于预期。本轮不验证 `context` 和 `NO_TIME=0`；Full/Delta
地址、resync、确定性 lossless 压力和 `TRACE_STATE=0` 停止功能保留已有结果证据。

本交接版本不验证 context。`NO_CONTEXT=0` 的 F3 context payload 分支和
Rocket `ctx` 端口保持未实现；decoder 使用固定的 `nocontext_p=true` profile。
之前生成的 context 结果目录仅作为历史诊断保留，不计入验收。

当前不能宣称“所有 tracer 功能已完成”。以下项目仍应在后续工作中处理或明确
保持未实现：

- `SHALLOW_TRACE` 已有 `te_packet_emitter` 单元时序证据，但 Tapeout 端到端
  workload 尚未隔离出独立于普通 F1 flush 的 decoder-visible 差异；
- `NO_CONTEXT=0` / context：按本轮范围不验证，RTL datapath 保持未实现；
- `TraceLost` sideband 目前硬连 `1'b0`；
- `IMPLICIT_EXCEPTION`、`IMPLICIT_RETURN`、`SIJUMP`、branch prediction、JTC
  只有可写寄存器，尚无 RTL 数据通路。

交接时必须保留脏工作树，不使用 broad `git reset/checkout/clean`。任何后续
RTL/Scala/decoder 修改后，都必须重新执行文档中的强制全量 VCS 构建和相关回归，
不能复用旧 `simv` 结果。

> 交接状态（2026-09-12）：`TapeoutRocketConfig` 的强制全量 VCS 构建，以及
> TVAL/CAUSE/TVEC/IADDR/特权过滤，以及 `mret`、Full/Delta 地址和
> resync 的定向 VCS -> SPI -> `pulp_chipyard` 解码链路均已有保留证据。
> **不可将该状态表述为所有可写寄存器模式都已支持**：`NO_CONTEXT=0` 的
> context datapath 未实现；可选
> 压缩/预测模式在 RTL 中没有完整数据通路；`TraceLost` 没有真实 sideband，
> 但确定性 lossless 压力已完成无死锁且 decoder 全量重建。中断覆盖按约定不在
> 本轮范围内。

## Scope and non-negotiable constraints

The objective is complete functional verification of the PULP `rv_tracer`
backend using only this acceptance path: `TapeoutRocketConfig`,
`nix develop .#default`, VCS, SPI trace deframing, then `riscv-etrace`
`pulp_chipyard` reconstruction.

The implementation is RV64. On the wire, `cause` and `tval` are 64-bit; do
not narrow them in RTL. `tval` is reconstructed as a full 64-bit value by the
decoder. The present public `trap::Info.ecause` API is `u16`, so it retains
only the low 16 bits after the decoder has consumed the 64-bit wire field.
Consequently, the completed CAUSE tests validate architectural low causes
(such as 1 and 8), not arbitrary high-bit `cause` reconstruction. Do not add a
FIFO or other material storage/area to resolve transport behavior. Lossless
flow control must use the existing clock-enable approach. Interrupt coverage
is explicitly out of scope.

The repository is dirty, including submodules. Preserve unrelated changes; do
not use broad `reset`, `checkout`, or `clean` operations.

## Current source state

### Lossless transport

The no-extra-storage repair uses a synchronous clock enable, not a generated
clock:

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni)
  if (!rst_ni) ...
  else if (encoder_ready) ...
```

`rv_tracer.sv` derives `encoder_ready` from encapsulator readiness in lossless
mode and applies it to priority, packet emission, branch-map, and resync state.
Do not replace it with `always_ff @(posedge clk_gated ...)`.

### RV64 sideband and decoder

The Rocket-to-PULP path carries `tvec` and `epc` through
`TraceCoreInterface`, `PulpRvTracer`, and the PULP wrapper. The decoder stays
RV64 in `dependencies/riscv-etrace/examples/pulp_chipyard.rs` and
`dependencies/riscv-etrace/examples/pulp_chipyard.toml`. Keep
`ecause_width_p=64`, `iaddress_width_p=64`, and `iaddress_lsb_p=0`.

`Trap::decode` in `src/packet/sync.rs` consumes `ecause_width_p` bits as a
`u64`, then currently casts that value to `u16` for `trap::Info.ecause`. This
is a decoder API limitation, not permission to change the RTL wire width. A
future high-bit CAUSE requirement needs a deliberate public API/type change
and a matching regression.

### Deterministic TVEC test setup

`applications/tests/trace/test_exception_filter_real.c` now clears delegation
after programming `mtvec` and before entering U mode:

```c
asm volatile("csrw medeleg, zero" ::: "memory");
```

This is a test determinism repair, not a tracer RTL change. Without it,
Rocket can delegate U-mode ECALL (`cause=8`) via an uninitialized `stvec`,
which produced a bogus target such as `0x000000e6b8024300`; the later
instruction-access fault reaches `mtvec` and falsely suggests TVEC sideband
alignment is broken.

## Fresh VCS build requirement

`soc-generator/sims/vcs/Makefile` accepts `VCS_FORCE_FULL=1`. It passes
`-noIncrComp` to VCS and removes only the exact target `simv` before linking,
preventing reuse of an old simulator binary. Every acceptance run must start
with:

```bash
nix develop .#default --command bash -lc \
  'make -B -C soc-generator/sims/vcs SIM=vcs CONFIG=TapeoutRocketConfig VCS_FORCE_FULL=1'
```

Latest successful forced build provenance (Full-address fix plus resync probe):

- `trace_verification/tapeout_vcs_forced_fresh_build_resyncprobe_20260912.rc`:
  `0`
- `trace_verification/tapeout_vcs_forced_fresh_build_resyncprobe_20260912.log`:
  VCS invocation includes `-noIncrComp` and reports `All of 173 modules done`.

VCS may still print `simv ... up to date` after its full compilation summary.
The provenance criteria are the requested option, actual module compilation,
and updated `simv` timestamp, not absence of that informational line.

Latest successful forced build provenance (TRACE_STATE qualification fix):

- `trace_verification/tapeout_vcs_forced_fresh_build_tracestatefix_20260912.rc`:
  `0`
- `trace_verification/tapeout_vcs_forced_fresh_build_tracestatefix_20260912.log`:
  includes `-noIncrComp` and `All of 173 modules done`.

### Final default-mode regression refresh

Context-revert refresh (2026-09-12): after the forced full VCS rebuild
`tapeout_vcs_forced_fresh_build_context_revert_20260912.log` (rc 0), the same 18
non-time/non-context workloads were rerun. The return-code index is
`final_tracestatefix_regression_summary.txt`; the run log is
`context_revert_non_time_regression_20260912.log`. All simulations and deframing
returned 0; decoder 2 appears only for expected fully excluded traces.

After the TRACE_STATE repair, 18 existing TVAL/CAUSE/TVEC/IADDR/privilege/`mret`
workloads were rerun on the latest forced full VCS binary. The authoritative
return-code index is
`trace_verification/final_tracestatefix_regression_summary.txt`; the per-case
artifacts are under
`trace_verification/result/tapeout_*_final_tracestatefix_20260912/`.
Every simulation and deframe return code is `0`. Decoder `0` denotes an
included trace, and decoder `2` is the documented expected outcome for a
fully excluded trace. The CAUSE-range exclusion is intentionally decoder `0`
because its setup leaves pre-ECALL M-mode instructions reconstructible.

## Verified functionality

All entries below used VCS -> SPI -> decoder. Result directories retain
`sim.log`, `sim.rc`, `trace.nibbles`, `trace.bin`, `deframe.log`,
`deframe.rc`, `decode.log`, and `decode.rc`.

| Feature | Result / evidence | Status |
| --- | --- | --- |
| Lossy stress / `TraceLost` | Earlier directory `result/tapeout_lossy_startfix_clockenable/` is superseded: serializer busy was incorrectly presented as loss. The current RTL hardwires `tc_packets_lost_i=1'b0` and has no real loss sideband. | **Not accepted / unimplemented semantics** |
| U-mode ECALL trap | `result/tapeout_privilege_exception_tval_control/`; User `Trap`, `ecause=8`, `tval=Some(0)` | Verified |
| TVAL equality include/exclude | `result/tapeout_test_tval_match_final_rebuilt_20260912/` has User Trap `ecause=8,tval=Some(0)`; `result/tapeout_test_tval_exclude_final_rebuilt_20260912/` has Support only and `instructions=0`. | Verified |
| CAUSE equality include/exclude | `result/tapeout_test_tval_match_final_rebuilt_20260912/` covers equality include (`cause=8`); `result/tapeout_test_cause_equal_exclude_final_rebuilt_20260912/` has Support only and `instructions=0`. | Verified |
| CAUSE range include/exclude | `result/tapeout_test_cause_range_match_final_rebuilt_20260912/` has User Trap `ecause=8,tval=Some(0)`; `result/tapeout_test_cause_range_exclude_final_rebuilt_20260912/` has no Trap. Its eight reconstructed instructions are pre-ECALL M-mode instructions intentionally left outside the U-mode privilege filter. | Verified |
| TVEC equality include/exclude | `result/tapeout_test_tvec_equal_match_final_rebuilt_20260912/` has User Trap `ecause=8,tval=Some(0)`; `result/tapeout_test_tvec_equal_exclude_final_rebuilt_20260912/` has Support only and `instructions=0`. | Verified |
| TVEC range include/exclude | `result/tapeout_test_tvec_range_match_final_rebuilt_20260912/` has User Trap `ecause=8,tval=Some(0)`; `result/tapeout_test_tvec_range_exclude_final_rebuilt_20260912/` has Support only and `instructions=0`. | Verified |
| IADDR equality include/exclude | `result/tapeout_test_iaddr_equal_match_final_rebuilt_20260912/` Start is `0x8000032c`, equal to its ELF `traced_block`; `result/tapeout_test_iaddr_equal_exclude_final_rebuilt_20260912/` has zero instructions. | Verified |
| IADDR range include/exclude | `result/tapeout_test_iaddr_range_match_final_rebuilt_20260912/` Start is `0x80000314`, equal to its ELF `traced_block`; `result/tapeout_test_iaddr_range_exclude_final_rebuilt_20260912/` has zero instructions. | Verified |
| Privilege M equality include | `result/tapeout_test_privilege_m_equal_iaddr_match_final_rebuilt_20260912/`; Machine Start at selected IADDR `0x8000032c`. | Verified |
| Privilege U/S range excludes M | `result/tapeout_test_privilege_us_range_iaddr_exclude_m_final_rebuilt_20260912/`; same selected IADDR and zero instructions. | Verified exclusion |
| RV64 high-half TVAL range, match | `result/tapeout_test_tval_range_high_match_final_decoderfix_20260912/`; `sim.rc=0`, `deframe.rc=0`, `decode.rc=0`; RTL reports `tval=0x0000000100000000`, decoder emits `tval=Some(4294967296)`. | Verified |
| RV64 high-half TVAL range, exclude | `result/tapeout_test_tval_range_high_exclude_final_decoderfix_20260912/`; the RTL has the same 64-bit TVAL, SPI has Support only, decoder reports `packets=1 instructions=0 skipped=0`, `decode.rc=2`. | Verified exclusion |
| `mret` to U-mode then U ECALL | `result/tapeout_test_mret_user_trap_final_rebuilt_20260912/`; all three return codes are `0`. `test_mret_objdump.log` contains `csrw medeleg,zero` and `mret`; RTL reports U-mode ECALL at `tvec=0x800002d0`, decoder reports a User Trap with `ecause=8,tval=Some(0)`. | Verified |
| Delta address mode | `result/tapeout_test_address_delta_mode_final_20260912/`; all three return codes are `0`, Support has `delta_address=true,full_address=false`, and decoder reconstructs 114 instructions. | Verified transport/configuration |
| Full address mode | `result/tapeout_test_address_full_mode_final_fulladdressfix_20260912/`; all three return codes are `0`, Support has `delta_address=false,full_address=true`, and F1/F2 addresses are nonzero valid ELF PCs. The prior result with zero F1/F2 addresses is superseded. | Verified |
| `NO_TIME=0`, `NO_CONTEXT=1` | 本轮不验证；历史 `tapeout_test_time_trace_final_20260912` 结果仅作参考，不纳入本轮验收。 | Out of scope |
| `TRACE_STATE` software stop | `result/tapeout_test_tracestate_disable_fixed_20260912/` runs the control ELF that previously traced its entire post-stop 10000-iteration delay. On the latest forced VCS binary it has only 5 SPI packets / 29 wire bytes after `TRACE_STATE=0`, versus 349 packets before the fix. VCS, deframe, and decoder return `0`. | Verified |
| Resynchronization threshold | `result/tapeout_test_lossless_resync_final_20260912/`; all three return codes are `0`. RTL logs seven `PULP_RTL_RESYNC` observations, and decoder logs subsequent Start synchronization packets. The source threshold is `MAX_VALUE=13'h1fff` cycle mode. | Verified |
| Sustained lossless stress | `result/tapeout_test_lossless_minimal_verified_final_tracestatefix_20260912/` uses a deterministic RV64 branch loop with `2046 = 31 x 66` conditional branches. VCS, deframe, and decoder all return `0`; SPI reports 69 packets / 481 wire bytes, and the decoder reports `instructions=9974 skipped=0`. Its filter is restricted to `dense_branch_loop`, so setup, drain, and UART diagnostic code do not contribute branch-map payloads. This is the accepted no-deadlock/no-reconstruction-loss stress proof. | Verified |
| `SHALLOW_TRACE` | Nix-environment VCS unit test `te_packet_emitter_shallow_vcs_20260912.log` passes: a non-F1 packet flushes only with `shallow_trace_i=1`, while F1 flushes in both modes. Tapeout results still do not isolate a decoder-visible difference from normal F1 flushing. | RTL unit verified; end-to-end not independently verified |
| `NO_CONTEXT=0` / context | 本轮明确不验证；`te_packet_emitter.sv` 的 `time_and_context=2'b01/2'b11` 仍为 TODO，wrapper/Scala 不传 context，decoder 固定 `nocontext_p=true`。 | Out of scope / unimplemented |
| `IMPLICIT_EXCEPTION`, `IMPLICIT_RETURN`, `SIJUMP`, branch prediction, JTC | Registers are writable, but `rv_tracer.sv` leaves their sideband/optional F0 ports commented and `te_packet_emitter.sv` leaves F0 optional-extension emission inside a comment block. | Unimplemented |

### Decoder exit-code rule for exclusion tests

`dependencies/riscv-etrace/examples/pulp_chipyard.rs` exits with code `2` if
reconstruction contains zero instructions. Therefore, for a filter-exclude
case, this is expected success rather than a decoder failure:

```text
PULP_ETRACE_RECONSTRUCT packets=1 instructions=0 skipped=0
decode.rc=2
```

This behavior occurs for both TVEC exclusion result directories above.

## Remaining acceptance gaps

1. `SHALLOW_TRACE` still needs a focused Tapeout workload where flushing a nonempty branch
   map changes the next decoder-visible packet. A same-source static baseline
   was added and run (`test_shallow_trace_baseline`), but separate ELF links
   changed code layout and therefore do not isolate the bit. A same-ELF
   runtime-toggle probe (`test_shallow_toggle`) was attempted and failed before
   tracing (`tohost=6`, zero packets), so it is not evidence of shallow
   behavior. APB readback or a successful run alone is insufficient.
2. `TraceLost`, implicit exception/return, SIJUMP, branch
   prediction, and JTC require RTL datapaths before a functional test can
   exist. Do not report them as verified based on their APB bits.

## Key files

- Filter/trap test: `applications/tests/trace/test_exception_filter_real.c`
- IADDR test: `applications/tests/trace/test_address_fixed.c`
- Deterministic lossless proof: `applications/tests/trace/test_lossless_minimal.c`
  (`test_lossless_minimal_verified`, with `DENSE_LOOP_ITERATIONS=2046UL`)
- Existing privilege test: `applications/tests/trace/test_privilege_fixed.c`
- Test target definitions: `applications/tests/CMakeLists.txt`
- Filter registers and mode fields:
  `soc-generator/generator/rocket-chip/src/main/resources/vsrc/rv_tracer/te_reg.sv`
- Filter datapath:
  `soc-generator/generator/rocket-chip/src/main/resources/vsrc/rv_tracer/te_filter.sv`
- Event priority and packet emission:
  `soc-generator/generator/rocket-chip/src/main/resources/vsrc/rv_tracer/te_priority.sv`,
  `soc-generator/generator/rocket-chip/src/main/resources/vsrc/rv_tracer/te_packet_emitter.sv`
- Rocket adapter:
  `soc-generator/generator/rocket-chip/src/main/scala/trace/PulpRvTracer.scala`
- Decoder entry/config: `dependencies/riscv-etrace/examples/pulp_chipyard.rs`,
  `dependencies/riscv-etrace/examples/pulp_chipyard.toml`; generic sync packet
  decode is in `dependencies/riscv-etrace/src/packet/sync.rs`.

Recent implementation repairs that require regression after every further RTL
change:

- `PulpRvTracer.scala` converts Rocket's retired-instruction bit into PULP
  halfword count (`2^ilastsize`), fixing RV64I reconstructed PCs previously
  offset by `-2`.
- `te_priority.sv` has a `tc_exception_i` trap path to align a qualified
  precise exception with current-stage cause/TVAL.
- The transport no longer fabricates `TraceLost` from a temporarily busy
  serializer. There is presently no true loss sideband, so lossy `TraceLost`
  behavior must be re-specified or explicitly marked unimplemented before
  accepting a lossy-stress claim.
- The PULP decoder derives F3/SF1 address width from the byte-rounded PULP
  payload length, then reads the following TVAL as 64 bits. The regression
  `pulp_trap_compressed_address_keeps_rv64_tval_aligned` uses the real 23-byte
  high-half packet shape; the complete `cargo test --features alloc,elf,serde`
  suite passes 354 tests plus 6 doctests.
- The PULP decoder also derives byte-rounded F3/SF0 Start address width. Its
  `--time` profile enables a 64-bit packet time field while keeping context
  disabled; the VCS time-mode result verifies this profile.
- `te_packet_emitter.sv` now preserves the selected full F1/F2 address. It
  previously overwrote it unconditionally with `diff_addr`, which is zero in
  Full-address mode. This is a combinational fix with no added state or FIFO.
- `rv_tracer.sv` now gates filter qualification with the APB-visible
  `trace_activated` state. The former controller-enable edge latch remained
  high after `TRACE_STATE=0` and caused tracing to continue. This is a
  combinational enable change with no added state or storage.

The shallow comparison artifacts are retained for handoff:

- `result/tapeout_test_shallow_trace_focus_20260912/`: shallow=1,
  `0/0/0`, 186 packets, 269 reconstructed instructions.
- `result/tapeout_test_shallow_trace_focus_baseline_20260912/`: shallow=0,
  `0/0/0`, 192 packets, 320 reconstructed instructions; not accepted as an
  isolated semantic comparison because the ELF layout differs.
- `result/tapeout_test_shallow_toggle_nofilter_20260912/`: same-ELF toggle
  probe, simulator reports `tohost=6`, zero packets; not accepted.
- `tapeout_vcs_forced_fresh_build_shallowtoggle_20260912.log` and `.rc`:
  latest forced full VCS build, `-noIncrComp`, 173 modules, return code 0.
- `riscv_etrace_cargo_test_20260912.log` and `.rc`: decoder/unit regression,
  354 tests plus 6 doctests, all passed (return code 0).
- `te_packet_emitter_shallow_vcs_20260912.log` and `.rc`: Nix VCS unit
  simulation, `SHALLOW_EMITTER_PASS`, return code 0. VCS emitted only the
  existing payload-width warning in unexercised optional packet branches.

TVEC APB words for RV64 are upper range `0x08/0x09`, lower range `0x0a/0x0b`,
match `0x0c/0x0d`, and control/mode `0x01`.

## Standard execution sequence

Rebuild an ELF after changing its source or CMake target:

```bash
nix develop .#default --command make -C applications/tests/build TEST
```

Then run the fresh simulator and preserve all artifacts:

```bash
nix develop .#default --command \
  soc-generator/sims/vcs/simv-chipyard.harness-TapeoutRocketConfig \
  +permissive +notimingcheck \
  +loadmem=applications/tests/build/TEST.riscv \
  +max-cycles=5000000 \
  +trace_spi_nibbles=trace_verification/result/NAME/trace.nibbles \
  +permissive-off applications/tests/build/TEST.riscv

python3 applications/tests/trace/deframe_trace_spi.py \
  trace_verification/result/NAME/trace.nibbles \
  trace_verification/result/NAME/trace.bin

nix develop .#default --command bash -lc \
  'cd dependencies/riscv-etrace && \
   target/release/examples/pulp_chipyard \
   ../../trace_verification/result/NAME/trace.bin \
   ../../applications/tests/build/TEST.riscv'
```

Do not accept `sim.rc=0` alone. Check packet type, privilege, exception cause,
`tval`, address/filter behavior, reconstructed instruction count, and the
documented zero-instruction exclusion rule.

## Recommended continuation order

1. Rebuild every workload ELF after its source changes. Specifically verify
   `csrw medeleg, zero` with objdump before accepting U-mode ECALL tests.
2. Validate `SHALLOW_TRACE` with a nonempty map and a non-F1 synchronization
   packet; all currently attempted trap boundaries emitted F1 first and thus
   used the normal unconditional flush path.
3. Validate configuration/address/resync modes.
4. Inspect and classify optional compression/prediction modes before creating
   tests.
5. Re-run every accepted case after any RTL, Scala, wrapper, Makefile, or
   decoder change with `VCS_FORCE_FULL=1`, then publish a matrix containing
   `verified`, `excluded as expected`, `unimplemented`, or `not yet tested`.
