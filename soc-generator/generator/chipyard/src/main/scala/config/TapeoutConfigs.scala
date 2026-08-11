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
  new chipyard.clocking.WithNdmResetInSystemReset ++
  new WithTapeoutSingleClock(100) ++
  new chipyard.harness.WithSimTSIOverSerialTL(fast = true) ++
  // Keep tapeout-style pads while attaching the behavioral EEPROM in the
  // simulation harness used by TapeoutConfig VCS regressions.
  new chipyard.harness.WithSimI2CEepromOnPads ++
  new chipyard.WithSerialConnect ++

  // Replace AbstractConfig's SPI/I2C punchthrough ports with General IO cells.
  // IOCellKey remains GenericIOCellParams for simulation and must be replaced
  // with the PDK General IO implementation before physical tapeout.
  new chipyard.iobinders.WithSPIIOCells ++
  new chipyard.iobinders.WithSimI2CIOCells ++
  // MMIO peripherals.  AbstractConfig supplies a default UART; replace it
  // here so this tapeout configuration owns the complete peripheral map.
  new chipyard.config.WithUART(
    baudrate = 115200,
    address = 0x10020000,
    txEntries = 8,
    rxEntries = 8) ++
  new chipyard.config.WithNoUART ++
  new chipyard.config.WithSPI(address = 0x10031000) ++
  new chipyard.config.WithI2C(address = 0x10040000) ++
  new chipyard.config.WithGPIO(address = 0x10010000, width = 8) ++

  new chipyard.config.AbstractConfig)


/**
 * TapeoutConfig with the SPI flash simulation target. The I2C EEPROM model is
 * already part of TapeoutConfig so its VCS image can run I2C regressions.
 */
class TapeoutSimConfig extends Config(
  new chipyard.harness.WithSimSPIFlashOnPads ++
  new chipyard.iobinders.WithSimSPIIOCells ++
  new TapeoutConfig)


// Rocket tile and cache sizing for the tapeout target.
class WithTapeoutRocket extends Config(
  // 64B line, direct-mapped: 64 sets * 1 way * 64B = 4 KiB per L1 cache.
  new freechips.rocketchip.rocket.WithL1ICacheSets(64) ++
  new freechips.rocketchip.rocket.WithL1ICacheWays(1) ++
  new freechips.rocketchip.rocket.WithL1DCacheSets(64) ++
  new freechips.rocketchip.rocket.WithL1DCacheWays(1) ++
  // Keep the default 8-way associativity: 16 KiB / (8 ways * 64B) = 32 sets.
  new freechips.rocketchip.subsystem.WithInclusiveCacheDirReg(true) ++
  new freechips.rocketchip.subsystem.WithInclusiveCacheSchedulerBypass(false) ++
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
