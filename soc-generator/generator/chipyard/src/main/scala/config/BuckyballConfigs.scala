package chipyard

import org.chipsalliance.cde.config.Config
import chipyard.buckyball.WithPebbleBuckyballRoCC

/** Rocket + Pebble Buckyball RoCC for Verilator regressions (no SMIC tapeout extras). */
class PebbleRocketConfig extends Config(
  new WithPebbleBuckyballRoCC ++
  new freechips.rocketchip.rocket.WithNHugeCores(1) ++
  new chipyard.config.AbstractConfig)
