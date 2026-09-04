package chipyard

import java.nio.file.{Files, Paths}

import chisel3._
import chisel3.util.log2Ceil

import org.chipsalliance.cde.config.{Config, Field, Parameters}
import org.chipsalliance.diplomacy.bundlebridge.BundleBridgeSource
import org.chipsalliance.diplomacy.lazymodule.{InModuleBody, LazyModule, LazyModuleImp}

import freechips.rocketchip.devices.debug.UseSMIC180DebugROM
import freechips.rocketchip.devices.tilelink.{BootROMLocated, BootROMParams}
import freechips.rocketchip.diplomacy.{AddressSet, RegionType, TransferSizes}
import freechips.rocketchip.resources.{Resource, SimpleDevice}
import freechips.rocketchip.subsystem.{BaseSubsystem, HasHierarchicalElements, HasTileInputConstants, TLBusWrapperLocation}
import freechips.rocketchip.tilelink.{TLFragmenter, TLManagerNode, TLSlaveParameters, TLSlavePortParameters}
import freechips.rocketchip.util.{ResourceFileName, SystemFileName}

/** Select the SMIC 180 nm synchronous ROM macro for BootROM instances. */
case object UseSMIC180BootROM extends Field[Boolean](false)

class WithSMIC180BootROM extends Config((_, _, _) => {
  case UseSMIC180BootROM => true
})

private object SMIC180ROMBuild {
  def enabled: Boolean = sys.env.get("SMIC180_ROM_ENABLED").exists { value =>
    value.trim.equalsIgnoreCase("1") ||
      value.trim.equalsIgnoreCase("yes") ||
      value.trim.equalsIgnoreCase("true")
  }
}

/** Select the hard BootROM and Debug ROM only when the build explicitly enables them.
  *
  * The effective value is supplied by chipyard.mk rather than reading the
  * user's raw command-line variable directly. This lets the Make flow mask
  * the option for configurations such as the P2E platform.
  */
class WithSMIC180BootROMFromEnv extends Config((_, _, _) => {
  case UseSMIC180BootROM => SMIC180ROMBuild.enabled
  case UseSMIC180DebugROM => SMIC180ROMBuild.enabled
})

class SMIC180BootROMMacro extends BlackBox {
  override def desiredName: String = SMIC180BootROM.macroName

  val io = IO(new Bundle {
    val Q = Output(UInt(SMIC180BootROM.dataBits.W))
    val A = Input(UInt(SMIC180BootROM.addressBits.W))
    val CLK = Input(Clock())
    val CEN = Input(Bool())
  })
}

/**
  * TileLink BootROM backed by the SMIC S018VM synchronous ROM macro.
  *
  * The macro reads on the rising clock edge when CEN is low. A TileLink Get is
  * accepted when the previous response slot is free, and its AccessAck is held
  * until the caller accepts it on the following cycle.
  */
class SMIC180TLROM(
  val base: BigInt,
  val size: Int,
  contentsDelayed: => Seq[Byte],
  beatBytes: Int,
  resources: Seq[Resource]
)(implicit p: Parameters) extends LazyModule {
  require(beatBytes == SMIC180BootROM.beatBytes,
    s"${SMIC180BootROM.macroName} requires ${SMIC180BootROM.beatBytes}-byte TileLink beats")
  require(size == SMIC180BootROM.sizeBytes,
    s"${SMIC180BootROM.macroName} is fixed at ${SMIC180BootROM.sizeBytes} bytes")

  val node = TLManagerNode(Seq(TLSlavePortParameters.v1(
    Seq(TLSlaveParameters.v1(
      address = List(AddressSet(base, size - 1)),
      resources = resources,
      regionType = RegionType.UNCACHED,
      executable = true,
      supportsGet = TransferSizes(1, beatBytes),
      fifoId = Some(0))),
    beatBytes = beatBytes)))

  lazy val module = new Impl

  class Impl extends LazyModuleImp(this) {
    private val contents = contentsDelayed
    require(contents.length <= size,
      s"BootROM image (${contents.length} bytes) exceeds SMIC macro capacity ($size bytes)")

    val (in, edge) = node.in(0)
    val macroRom = Module(new SMIC180BootROMMacro)
    val pending = RegInit(false.B)
    val requestBits = Reg(chiselTypeOf(in.a.bits))
    val request = in.a.fire

    // The macro samples the TileLink address at the request edge. Its Q output
    // is stable throughout the subsequent response cycle.
    macroRom.io.A := in.a.bits.address(log2Ceil(size) - 1, log2Ceil(beatBytes))
    macroRom.io.CLK := clock
    macroRom.io.CEN := !request

    // Do not accept a new request on the response-consumption edge. The
    // synchronous macro updates Q on that edge, so a one-cycle bubble keeps
    // the old response data stable for the complete D transaction.
    in.a.ready := !pending
    in.d.valid := pending
    in.d.bits := edge.AccessAck(requestBits, macroRom.io.Q)

    when(request) {
      requestBits := in.a.bits
    }
    pending := (pending && !in.d.ready) || request

    in.b.valid := false.B
    in.c.ready := true.B
    in.e.ready := true.B
  }
}

object SMIC180BootROM {
  val macroName = "S018VM_X64Y16D64_PM"
  val beatBytes = 8
  val dataBits = beatBytes * 8
  val sizeBytes = 0x2000
  val addressBits = log2Ceil(sizeBytes / beatBytes)

  def contents(params: BootROMParams, subsystem: BaseSubsystem): Seq[Byte] = {
    val image = params.contentFileName match {
      case SystemFileName(fileName) => Files.readAllBytes(Paths.get(fileName)).toIndexedSeq
      case ResourceFileName(fileName) => os.read.bytes(os.resource / os.RelPath(fileName.dropWhile(_ == '/'))).toIndexedSeq
    }
    if (params.appendDTB) image ++ subsystem.dtb.contents else image.toIndexedSeq
  }

  def attach(
    params: BootROMParams,
    subsystem: BaseSubsystem with HasHierarchicalElements with HasTileInputConstants,
    where: TLBusWrapperLocation
  )(implicit p: Parameters): SMIC180TLROM = {
    require(params.size == sizeBytes,
      s"${macroName} requires a ${sizeBytes / 1024} KiB BootROM, got ${params.size} bytes")

    val tlbus = subsystem.locateTLBusWrapper(where)
    val domain = tlbus.generateSynchronousDomain(params.name).suggestName(s"${params.name}_domain")
    val resetVectorSource = BundleBridgeSource[UInt]()
    lazy val bootROMContents = contents(params, subsystem)
    val bootrom = domain {
      LazyModule(new SMIC180TLROM(
        params.address,
        params.size,
        bootROMContents,
        tlbus.beatBytes,
        new SimpleDevice("rom", Seq("sifive,rom0")).reg("mem")))
    }

    bootrom.node := tlbus.coupleTo(params.name) { TLFragmenter(tlbus, Some(params.name)) := _ }
    if (params.driveResetVector) {
      subsystem.tileResetVectorNexusNode := resetVectorSource
      InModuleBody {
        val resetVector = resetVectorSource.bundle
        require(resetVector.getWidth >= params.hang.bitLength,
          s"BootROM reset vector ${params.hang} exceeds physical address width ${resetVector.getWidth}")
        resetVectorSource.bundle := params.hang.U
      }
    }
    bootrom
  }
}
