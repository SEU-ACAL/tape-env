package chipyard.iobinders

import chisel3._
import chisel3.experimental.Analog

import org.chipsalliance.diplomacy.lazymodule.InModuleBody
import freechips.rocketchip.diplomacy.{Resource, ResourceBinding, ResourceAddress}
import freechips.rocketchip.subsystem.BaseSubsystem

import sifive.blocks.devices.i2c.HasPeripheryI2C
import sifive.blocks.devices.spi.{HasPeripherySPI, MMCDevice}

/** Physical I2C pads made available only to simulation harness binders. */
case class SimI2CPadPort(
  val getScl: () => Analog,
  val getSda: () => Analog,
  val i2cId: Int)
    extends Port[Analog] {
  val getIO: () => Analog = getScl
  lazy val scl: Analog = getScl()
  lazy val sda: Analog = getSda()
}

/** Physical SPI pads made available only to simulation harness binders. */
case class SimSPIPadPort(
  val getSck: () => Analog,
  val getCs: Seq[() => Analog],
  val getDq: Seq[() => Analog],
  val spiId: Int)
    extends Port[Analog] {
  val getIO: () => Analog = getSck
  lazy val sck: Analog = getSck()
  lazy val cs: Seq[Analog] = getCs.map(_())
  lazy val dq: Seq[Analog] = getDq.map(_())
}

/**
  * Simulation-only version of [[WithI2CIOCells]].  It produces the same pad
  * names and IO cells as tapeout, while returning the pads to the harness so a
  * behavioral I2C target can be attached.
  */
class WithSimI2CIOCells extends OverrideIOBinder({
  (system: HasPeripheryI2C) => {
    val portsAndCells = system.i2c.zipWithIndex.map { case (i2c, i) =>
      val p = system.asInstanceOf[BaseSubsystem].p
      val sclPad = IO(Analog(1.W)).suggestName(s"i2c_${i}_scl")
      val sdaPad = IO(Analog(1.W)).suggestName(s"i2c_${i}_sda")

      val sclCell = p(IOCellKey).gpio().suggestName(s"iocell_i2c_${i}_scl")
      sclCell.io.o := i2c.scl.out
      sclCell.io.oe := i2c.scl.oe
      sclCell.io.ie := true.B
      i2c.scl.in := sclCell.io.i
      sclCell.io.pad <> sclPad

      val sdaCell = p(IOCellKey).gpio().suggestName(s"iocell_i2c_${i}_sda")
      sdaCell.io.o := i2c.sda.out
      sdaCell.io.oe := i2c.sda.oe
      sdaCell.io.ie := true.B
      i2c.sda.in := sdaCell.io.i
      sdaCell.io.pad <> sdaPad

      (SimI2CPadPort(() => sclPad, () => sdaPad, i), Seq(sclCell, sdaCell))
    }
    (portsAndCells.map(_._1), portsAndCells.flatMap(_._2))
  }
})

/**
  * Simulation-only version of [[WithSPIIOCells]].  It preserves the tapeout
  * pad topology while making the physical SPI nets available to a harness
  * model.
  */
class WithSimSPIIOCells extends OverrideLazyIOBinder({
  (system: HasPeripherySPI) => {
    if (system.tlSpiNodes.nonEmpty) {
      ResourceBinding {
        Resource(new MMCDevice(system.tlSpiNodes.head.device, 1), "reg").bind(ResourceAddress(0))
      }
    }
    InModuleBody {
      val p = system.asInstanceOf[BaseSubsystem].p
      val portsAndCells = system.spi.zipWithIndex.map { case (spi, i) =>
        val sckPad = IO(Analog(1.W)).suggestName(s"spi_${i}_sck")
        val sckCell = p(IOCellKey).gpio().suggestName(s"iocell_spi_${i}_sck")
        sckCell.io.o := spi.sck
        sckCell.io.oe := true.B
        sckCell.io.ie := false.B
        sckCell.io.pad <> sckPad

        val csPadsAndCells = spi.cs.zipWithIndex.map { case (cs, j) =>
          val csPad = IO(Analog(1.W)).suggestName(s"spi_${i}_cs_${j}")
          val csCell = p(IOCellKey).gpio().suggestName(s"iocell_spi_${i}_cs_${j}")
          csCell.io.o := cs
          csCell.io.oe := true.B
          csCell.io.ie := false.B
          csCell.io.pad <> csPad
          (csPad, csCell)
        }

        val dqPadsAndCells = spi.dq.zipWithIndex.map { case (dq, j) =>
          val dqPad = IO(Analog(1.W)).suggestName(s"spi_${i}_dq_${j}")
          val dqCell = p(IOCellKey).gpio().suggestName(s"iocell_spi_${i}_dq_${j}")
          dqCell.io.o := dq.o
          dqCell.io.oe := dq.oe
          dqCell.io.ie := dq.ie
          dq.i := dqCell.io.i
          dqCell.io.pad <> dqPad
          (dqPad, dqCell)
        }

        val port = SimSPIPadPort(
          () => sckPad,
          csPadsAndCells.map { case (pad, _) => () => pad },
          dqPadsAndCells.map { case (pad, _) => () => pad },
          i)
        (port, Seq(sckCell) ++ csPadsAndCells.map(_._2) ++ dqPadsAndCells.map(_._2))
      }
      (portsAndCells.map(_._1), portsAndCells.flatMap(_._2))
    }
  }
})
