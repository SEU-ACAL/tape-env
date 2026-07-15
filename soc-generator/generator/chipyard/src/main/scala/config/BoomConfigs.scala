package chipyard

import org.chipsalliance.cde.config.Config

/** A compact BOOMv3 system intended for RTL simulation and software bring-up. */
class SmallBoomV3Config extends Config(
  new boom.v3.common.WithNSmallBooms(1) ++
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
