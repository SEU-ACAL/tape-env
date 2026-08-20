package chipyard

import org.chipsalliance.cde.config.Config

/** A compact BOOMv3 system intended for RTL simulation and software bring-up. */
class SmallBoomV3Config extends Config(
  new boom.v3.common.WithNSmallBooms(1) ++
  new chipyard.config.AbstractConfig)

/** BOOMv3 FDIP configuration, including the FDIP frontend, ICache prefetch
  * pipeline, and FDIP-specific branch prediction path.
  */
class FDIPMegaBoomV3Config extends Config(
  new boom.fdip.common.WithNMegaBooms(1) ++
  new chipyard.config.WithSystemBusWidth(128) ++
  new chipyard.config.AbstractConfig)

/** FDIP Mega BOOM configuration with Spike commit cosimulation enabled. */
class FDIPMegaBoomV3CosimConfig extends Config(
  new chipyard.harness.WithCospike ++
  new chipyard.config.WithTraceIO ++
  new boom.fdip.common.WithFDIPBoomTrace ++
  new boom.fdip.common.WithNMegaBooms(1) ++
  new chipyard.config.WithSystemBusWidth(128) ++
  new chipyard.config.AbstractConfig)

/** FDIP Mega BOOM with counters enabled for frontend performance diagnosis. */
class FDIPMegaBoomV3CosimPerfConfig extends Config(
  new boom.perf.WithBoomXSPerf ++
  new chipyard.harness.WithCospike ++
  new chipyard.config.WithTraceIO ++
  new boom.fdip.common.WithFDIPBoomTrace ++
  new boom.fdip.common.WithNBoomPerfCounters(10) ++
  new boom.fdip.common.WithNMegaBooms(1) ++
  new chipyard.config.WithSystemBusWidth(128) ++
  new chipyard.config.AbstractConfig)

/** Same FDIP RTL as the cosim performance config, without host cosimulation. */
class FDIPMegaBoomV3PerfConfig extends Config(
  new boom.perf.WithBoomXSPerf ++
  new boom.fdip.common.WithNBoomPerfCounters(10) ++
  new boom.fdip.common.WithNMegaBooms(1) ++
  new chipyard.config.WithSystemBusWidth(128) ++
  new chipyard.config.AbstractConfig)

/** BOOMv3 Mega baseline for FDIP performance comparisons. */
class MegaBoomV3Config extends Config(
  new boom.v3.common.WithNMegaBooms(1) ++
  new chipyard.config.WithSystemBusWidth(128) ++
  new chipyard.config.AbstractConfig)

/** Coupled Mega BOOM baseline with counters enabled for FDIP comparisons. */
class MegaBoomV3PerfConfig extends Config(
  new boom.perf.WithBoomXSPerf ++
  new boom.v3.common.WithNBoomPerfCounters(10) ++
  new boom.v3.common.WithNMegaBooms(1) ++
  new chipyard.config.WithSystemBusWidth(128) ++
  new chipyard.config.AbstractConfig)


/** BOOMv3 configuration used by the upstream Verilator regression suite. */
class MediumBoomV3CosimConfig extends Config(
  new chipyard.harness.WithCospike ++
  new chipyard.config.WithTraceIO ++
  new boom.v3.common.WithNMediumBooms(1) ++
  new chipyard.config.AbstractConfig)

/** BOOMv3 cosimulation configuration for fast software regressions. */
class MediumBoomV3CosimFastConfig extends Config(
  new chipyard.harness.WithCospike ++
  new chipyard.config.WithTraceIO ++
  new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new boom.v3.common.WithNMediumBooms(1) ++
  new chipyard.config.AbstractConfig)

/** BOOMv4 configuration used by the upstream Verilator regression suite. */
class MediumBoomV4CosimConfig extends Config(
  new chipyard.harness.WithCospike ++
  new chipyard.config.WithTraceIO ++
  new boom.v4.common.WithNMediumBooms(1) ++
  new chipyard.config.AbstractConfig)

/** BOOMv4 cosimulation configuration for fast software regressions.
  *
  * TileLink protocol monitors are intentionally omitted. Pair this with
  * VERILATOR_ASSERTS=0 when protocol and assertion checking is unnecessary.
  */
class MediumBoomV4CosimFastConfig extends Config(
  new chipyard.harness.WithCospike ++
  new chipyard.config.WithTraceIO ++
  new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new boom.v4.common.WithNMediumBooms(1) ++
  new chipyard.config.AbstractConfig)
