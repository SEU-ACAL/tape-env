package testchipip.boot

import java.io.File
import scala.sys.process.Process

import org.chipsalliance.cde.config.Config
import freechips.rocketchip.devices.tilelink.BootROMLocated
import freechips.rocketchip.subsystem.PeripheryBusKey
import freechips.rocketchip.util.SystemFileName

private object TapeBootROM {
  private val sourceRelativePath =
    "soc-generator/generator/testchipip/src/main/resources/testchipip/tapebootrom"
  private var lastBuiltPBusFrequencyHz = Option.empty[BigInt]

  private def sourceDirectory: File = {
    val workingDirectory = new File(System.getProperty("user.dir")).getAbsoluteFile
    Iterator.iterate(workingDirectory)(_.getParentFile)
      .takeWhile(_ != null)
      .map(new File(_, sourceRelativePath))
      .find(_.isDirectory)
      .getOrElse(throw new IllegalArgumentException(
        s"Unable to locate Tape BootROM source directory from ${workingDirectory.getPath}"))
  }

  def image(pbusFrequencyHz: BigInt): File = synchronized {
    val directory = sourceDirectory
    val bootROMImage = new File(directory, "build/tapeboot.bin").getAbsoluteFile

    if (!lastBuiltPBusFrequencyHz.contains(pbusFrequencyHz)) {
      val exitCode = Process(Seq(
        "make", "-B", "-C", directory.getPath,
        s"PBUS_CLK=$pbusFrequencyHz", "bin")).!
      require(exitCode == 0, s"Failed to build Tape BootROM (exit code $exitCode)")
      lastBuiltPBusFrequencyHz = Some(pbusFrequencyHz)
    }

    require(bootROMImage.isFile, s"Tape BootROM image was not generated: ${bootROMImage.getPath}")
    bootROMImage
  }
}

/** Build and use the Tapeout-specific BootROM image. */
class WithTapeBootROM extends Config((site, here, up) => {
  case BootROMLocated(x) =>
    val pbusFrequencyHz = site(PeripheryBusKey).dtsFrequency.getOrElse(
      throw new IllegalArgumentException("Tape BootROM requires a defined PBUS frequency"))
    val bootROMImage = TapeBootROM.image(pbusFrequencyHz)
    up(BootROMLocated(x), site).map(_.copy(
      contentFileName = SystemFileName(bootROMImage.getPath)
    ))
})
