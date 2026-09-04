package chipyard

import org.chipsalliance.cde.config.Config
import testchipip.soc.{OBUS}
import freechips.rocketchip.subsystem.{MBUS}
import chipyard.buckyball.WithPebbleBuckyballRoCC
import freechips.rocketchip.devices.debug.DebugModuleKey
import freechips.rocketchip.util.{ClockGate, ClockGateImpl, ClockGateModelFile}
import chipyard.iobinders.IOCellKey
import chipyard.iocell.SMIC180IOCellParams

/** Select SMIC SP018RP IO wrappers for all Tapeout configurations. */
class WithSMIC180IOCells extends Config((site, here, up) => {
  case IOCellKey => SMIC180IOCellParams()
})

/** Map generic Rocket-Chip clock gates to SMIC UHD integrated clock gates. */
class SMIC180ClockGate extends ClockGate {
  override def desiredName = "SMIC180ClockGate"
}

class WithSMIC180ClockGates extends Config((site, here, up) => {
  case ClockGateImpl => () => new SMIC180ClockGate
  case ClockGateModelFile => Some("/vsrc/SMIC180ClockGate.v")
})

/** Keep the Debug Module inner clock running for Tapeout JTAG bring-up. */
class WithNoDebugClockGate extends Config((site, here, up) => {
  case DebugModuleKey => up(DebugModuleKey).map(_.copy(clockGate = false))
})

private object TapeoutSPIFlashModel {
  val enabled: Boolean = sys.env.get("TAPEOUT_ENABLE_SPI_FLASH_MODEL").exists { value =>
    value.trim.equalsIgnoreCase("1") ||
      value.trim.equalsIgnoreCase("yes") ||
      value.trim.equalsIgnoreCase("true")
  }

  val config: Config = if (enabled) {
    new chipyard.harness.WithSimSPIFlashOnPads
  } else {
    new Config((_, _, _) => PartialFunction.empty[Any, Any])
  }
}

/**
  * Tapeout target based on the current chip-like Rocket configuration.
  *
  * This separate config is the single place to add tapeout-specific overrides
  * while preserving the established core, IO, memory, and clocking choices.
  */

class TapeoutConfig extends Config(

  new WithSMIC180BootROMFromEnv ++
  new testchipip.boot.WithTapeBootROM ++
  // The tapeout boot image is linked into an 8 KiB ROM window.
  new chipyard.config.WithBootROM(size = 0x2000) ++
  // All Tapeout configurations use SMIC physical clock gates and IO wrappers.
  new WithSMIC180ClockGates ++
  new WithNoDebugClockGate ++
  new WithSMIC180IOCells ++
  new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  // If we don't have enough space, just comment this line below
  new WithPebbleBuckyballRoCC ++
  new WithTapeoutRocket ++
  // AbstractConfig adds an MBUS scratchpad; remove all subsystem scratchpads.
  new testchipip.soc.WithNoScratchpads ++
  new chipyard.clocking.WithNdmResetInSystemReset ++
  new WithTapeoutSingleClock(100) ++
  new chipyard.harness.WithSimTSIOverSerialTL(fast = true) ++
  // Keep tapeout-style pads while attaching the behavioral SPI Flash and I2C
  // models in the VCS harness used by TapeoutConfig regressions.
  new chipyard.harness.WithSimI2CEepromOnPads ++
  TapeoutSPIFlashModel.config ++
  new chipyard.WithSerialConnect ++

  // Replace AbstractConfig's SPI/I2C punchthrough ports with tapeout IO cells
  // while exposing the same pads to the behavioral VCS models.
  new chipyard.iobinders.WithSimSPIIOCells ++
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
  * Tapeout target with the same Rocket, IO, memory, and clocking settings as
  * TapeoutConfig, but without the Pebble Buckyball RoCC.
  */
class TapeoutRocketConfig extends Config(

  new WithSMIC180BootROMFromEnv ++
  new testchipip.boot.WithTapeBootROM ++
  new chipyard.config.WithBootROM(size = 0x2000) ++
  new WithSMIC180ClockGates ++
  new WithNoDebugClockGate ++
  new WithSMIC180IOCells ++
  new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new WithTapeoutRocket ++
  new testchipip.soc.WithNoScratchpads ++
  new chipyard.clocking.WithNdmResetInSystemReset ++
  new WithTapeoutSingleClock(100) ++
  new chipyard.harness.WithSimTSIOverSerialTL(fast = true) ++
  new chipyard.harness.WithSimI2CEepromOnPads ++
  TapeoutSPIFlashModel.config ++
  new chipyard.WithSerialConnect ++

  new chipyard.iobinders.WithSimSPIIOCells ++
  new chipyard.iobinders.WithSimI2CIOCells ++
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
  testchipip.serdes.CreditedSourceSyncSerialPhyParams(phitWidth=4, flitWidth=16))++
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
