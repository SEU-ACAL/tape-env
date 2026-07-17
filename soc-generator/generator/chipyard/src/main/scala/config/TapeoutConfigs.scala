package chipyard

import org.chipsalliance.cde.config.Config
import testchipip.soc.{OBUS}
import freechips.rocketchip.subsystem.{MBUS}



/**
  * Tapeout target based on the current chip-like Rocket configuration.
  *
  * This separate config is the single place to add tapeout-specific overrides
  * while preserving the established core, IO, memory, and clocking choices.
  */

class TapeoutConfig extends Config(

  new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new WithTapeoutRocket ++
  // AbstractConfig adds an MBUS scratchpad; remove all subsystem scratchpads.
  new testchipip.soc.WithNoScratchpads ++
  new WithTapeoutSingleClock(100) ++
  new chipyard.harness.WithSimTSIOverSerialTL(fast = true) ++
  new chipyard.WithSerialConnect ++
  new chipyard.config.AbstractConfig)

// Rocket tile and cache sizing for the tapeout target.
class WithTapeoutRocket extends Config(
  // 64B line, 8-way: 8 sets * 8 ways * 64B = 4 KiB per L1 cache.
  new freechips.rocketchip.rocket.WithL1ICacheSets(8) ++
  new freechips.rocketchip.rocket.WithL1DCacheSets(8) ++
  // Keep the default 8-way associativity: 16 KiB / (8 ways * 64B) = 32 sets.
  new freechips.rocketchip.subsystem.WithInclusiveCache(nWays = 8, capacityKB = 16) ++
  new freechips.rocketchip.rocket.WithNHugeCores(1)
)


// 串行接口
class WithSerialConnect extends Config (
  new testchipip.serdes.WithSerialTLMem(size = BigInt("10000000",16)) ++ // 8 GB of off-chip memory
  new testchipip.serdes.WithSerialTLPHYParams(
  testchipip.serdes.DecoupledExternalSyncSerialPhyParams(phitWidth=4, flitWidth=16))++
  new chipyard.config.WithSerialTLBackingMemory  ++
  new testchipip.soc.WithOffchipBusClient(MBUS) ++                                      // offchip bus connects to MBUS, since the serial-tl needs to provide backing memory
  new testchipip.soc.WithOffchipBus
)

// 单一时钟
class WithTapeoutSingleClock(freqMHz: Int) extends Config(
  new chipyard.clocking.WithSingleClockBroadcastClockGenerator(freqMHz) ++
  new chipyard.config.WithTileFrequency(freqMHz.toDouble) ++
  new chipyard.config.WithUniformBusFrequencies(freqMHz.toDouble) ++
  new chipyard.harness.WithHarnessBinderClockFreqMHz(freqMHz.toDouble) ++
  new chipyard.harness.WithAbsoluteFreqHarnessClockInstantiator
)
