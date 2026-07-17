package midas.targetutils

import chisel3._

/** Compatibility shims for legacy target instrumentation.
  *
  * These methods intentionally produce no annotations or synthesized printfs.
  */
object PerfCounter {
  def apply(target: UInt, label: String, description: String): Unit = ()
}

object SynthesizePrintf {
  def apply[T](printf: T): T = printf
  def apply(format: String, args: Bits*): Printable = Printable.pack("")
  def apply(name: String, format: String, args: Bits*): Printable = Printable.pack("")
}
