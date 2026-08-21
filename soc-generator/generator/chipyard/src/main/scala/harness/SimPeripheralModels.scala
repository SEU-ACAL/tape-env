package chipyard.harness

import chisel3._
import chisel3.experimental.{Analog, IntParam, StringParam}
import chisel3.util.HasBlackBoxResource

import freechips.rocketchip.util.PlusArgArtefacts
import testchipip.spi.SPIFlashPlusarg

/** Adapter for connecting the existing QSPI flash model to physical pad nets. */
class SimSPIFlashPadModel(capacityBytes: BigInt, id: Int, rdOnly: Boolean)
    extends BlackBox(Map(
      "PLUSARG" -> StringParam(SPIFlashPlusarg(id)),
      "READONLY" -> IntParam(if (rdOnly) 1 else 0),
      "CAPACITY_BYTES" -> IntParam(capacityBytes)))
    with HasBlackBoxResource {
  val io = IO(new Bundle {
    val sck = Analog(1.W)
    val cs = Analog(1.W)
    val dq = Vec(4, Analog(1.W))
    val reset = Input(Bool())
  })

  require(capacityBytes > 0 && capacityBytes < 0x100000000L,
    "SimSPIFlashPadModel requires a positive capacity below 4 GiB")
  PlusArgArtefacts.append(SPIFlashPlusarg(id), 0,
    s"Binary image to mount to SPI flash memory ${id}")

  addResource("/vsrc/SimSPIFlashPadModel.sv")
  addResource("/testchipip/vsrc/SimSPIFlashModel.sv")
  addResource("/testchipip/vsrc/SPIFlashMemCtrl.sv")
  addResource("/testchipip/vsrc/plusarg_file_mem.sv")
  addResource("/testchipip/csrc/plusarg_file_mem.cc")
  addResource("/testchipip/csrc/plusarg_file_mem.h")
}

/** A 256-byte, 7-bit-address I2C EEPROM model for controller verification. */
class SimI2CEepromModel(i2cAddress: Int = 0x50)
    extends BlackBox(Map("I2C_ADDRESS" -> IntParam(i2cAddress)))
    with HasBlackBoxResource {
  val io = IO(new Bundle {
    val scl = Analog(1.W)
    val sda = Analog(1.W)
    val reset = Input(Bool())
  })

  require(i2cAddress >= 0 && i2cAddress < 0x80,
    "SimI2CEepromModel requires a 7-bit I2C address")

  addResource("/vsrc/SimI2CEepromModel.sv")
}
