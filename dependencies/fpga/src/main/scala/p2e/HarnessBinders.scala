package chipyard.fpga.p2e

import chisel3._
import org.chipsalliance.diplomacy.nodes.{HeterogeneousBag}
import freechips.rocketchip.diplomacy._

import chipyard._
import chipyard.harness._
import chipyard.iobinders._
import testchipip.serdes._

/*** UART ***/
class WithUART extends HarnessBinder({
  case (th: P2EFPGATestHarnessImp, port: UARTPort, chipId: Int) => {
    th.vcu118Outer.io_uart_bb.bundle <> port.io
  }
})


/*** Experimental DDR ***/
class WithDDRMem extends HarnessBinder({
  case (th: P2EFPGATestHarnessImp, port: TLMemPort, chipId: Int) => {
    val bundles = th.vcu118Outer.ddrClient.out.map(_._1)
    val ddrClientBundle = Wire(new HeterogeneousBag(bundles.map(_.cloneType)))
    bundles.zip(ddrClientBundle).foreach { case (bundle, io) => bundle <> io }
    ddrClientBundle <> port.io
  }
})

class WithJTAG extends HarnessBinder({
  case (th: P2EFPGATestHarnessImp, port: JTAGPort, chipId: Int) => {
    val jtag_io = th.vcu118Outer.jtagPlacedOverlay.overlayOutput.jtag.getWrappedValue
    port.io.TCK := jtag_io.TCK
    port.io.TMS := jtag_io.TMS
    port.io.TDI := jtag_io.TDI
    port.io.reset.foreach(_ := th.referenceReset)
    jtag_io.TDO.data := port.io.TDO
    jtag_io.TDO.driven := true.B
    // ignore srst_n
    jtag_io.srst_n := DontCare

  }
})

class WithGPIO extends HarnessBinder({
  case (th: P2EFPGATestHarnessImp, port: GPIOPort, chipId: Int) => {

      th.gpio_pins(port.pinId) <> port.io
  }
})

class WithSPISDCard extends HarnessBinder({
  case (th: P2EFPGATestHarnessImp, port: SPIPort, chipId: Int) => {
    th.vcu118Outer.io_spi_bb.bundle <> port.io
  }
})

/** TLSerdes */
class WithSerialTL2DDR extends HarnessBinder({
  case (th: P2EFPGATestHarnessImp, port: SerialTLPort, chipId: Int) => {
    val bundles = th.vcu118Outer.ddrClient.out.map(_._1)
    val serial = LazyModule(new Serial(port.serdesser, port.params)(port.serdesser.p))
    val ddrClientBundle = Wire(new HeterogeneousBag(bundles.map(_.cloneType)))
    bundles.zip(ddrClientBundle).foreach { case (bundle, io) => bundle <> io }

    port.io match {
      case io: DecoupledExternalSyncPhitIO =>
        io.clock_in := th.fpgaClock
        val serialModule = withClockAndReset(th.fpgaClock, th.fpgaResetSigned) {
          Module(serial.module)
        }
        serialModule.io.ser.in <> io.out
        io.in <> serialModule.io.ser.out
        serialModule.io.tl <> ddrClientBundle(0)
      case other => {
        throw new IllegalArgumentException(s"P2E requires DecoupledExternalSyncPhitIO, got ${other.getClass}")
      }
    }
  }
})
