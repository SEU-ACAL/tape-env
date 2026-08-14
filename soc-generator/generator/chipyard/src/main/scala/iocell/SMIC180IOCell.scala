// See LICENSE for license details

package chipyard.iocell

import chisel3._
import chisel3.experimental.Analog

/**
  * Physical wrappers for the SMIC SP018RP digital IO library.
  *
  * The PDK Verilog model is intentionally not added as a Chisel resource. It is
  * proprietary collateral and must be supplied by the synthesis/P&R or gate-level
  * simulation flow. RTL simulation continues to use GenericIOCellParams.
  */
private class SMICPIR extends BlackBox {
  override def desiredName = "PIR"
  val io = IO(new Bundle {
    val PAD = Input(Bool())
    val C = Output(Bool())
  })
}

private class SMICPOT4R extends BlackBox {
  override def desiredName = "POT4R"
  val io = IO(new Bundle {
    // POT4R drives PAD and uses an active-low output enable.
    val PAD = Output(Bool())
    val OEN = Input(Bool())
    val I = Input(Bool())
  })
}

private class SMICPB4R extends BlackBox {
  override def desiredName = "PB4R"
  val io = IO(new Bundle {
    val PAD = Analog(1.W)
    val OEN = Input(Bool())
    val I = Input(Bool())
    val C = Output(Bool())
  })
}

/** SMIC PIR input pad, with the GenericDigitalInIOCell input-enable behavior. */
class SMIC180DigitalInIOCell extends RawModule with DigitalInIOCell {
  val io = IO(new DigitalInIOCellBundle)

  private val cell = Module(new SMICPIR)
  cell.io.PAD := io.pad
  io.i := Mux(io.ie, cell.io.C, false.B)
}

/** SMIC POT4R output pad. OEN is active low in the SP018RP library. */
class SMIC180DigitalOutIOCell extends RawModule with DigitalOutIOCell {
  val io = IO(new DigitalOutIOCellBundle)

  private val cell = Module(new SMICPOT4R)
  cell.io.I := io.o
  cell.io.OEN := !io.oe
  io.pad := cell.io.PAD
}

/** SMIC PB4R bidirectional pad, preserving GenericDigitalGPIOCell semantics. */
class SMIC180DigitalGPIOCell extends RawModule with DigitalGPIOCell {
  val io = IO(new DigitalGPIOCellBundle)

  private val cell = Module(new SMICPB4R)
  cell.io.I := io.o
  cell.io.OEN := !io.oe
  io.pad <> cell.io.PAD
  io.i := Mux(io.ie, cell.io.C, false.B)
}

case class SMIC180IOCellParams() extends IOCellTypeParams {
  def analog() = throw new UnsupportedOperationException(
    "SMIC180IOCellParams does not define an analog IO cell; add a PDK-specific analog wrapper first")
  def gpio() = Module(new SMIC180DigitalGPIOCell)
  def input() = Module(new SMIC180DigitalInIOCell)
  def output() = Module(new SMIC180DigitalOutIOCell)
}
