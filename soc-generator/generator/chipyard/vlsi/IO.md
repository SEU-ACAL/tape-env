# SMIC180 IO Cell Replacement

`TapeoutConfig` uses SP018RP pad cells directly and attaches the pad-connected
SPI/I2C simulation models in its VCS harness.

| Chipyard IO type | SP018RP cell | Current instance count |
| --- | --- | ---: |
| Digital input | `PIR` | 15 |
| Digital output | `POT8R` | 9 |
| GPIO / SPI / I2C | `PB8R` | 16 |

`POT8R` and `PB8R` have active-low `OEN`; the wrappers invert Chipyard's
active-high `oe` so the existing IO behavior is unchanged. `PIR` is used for
the digital input path to avoid adding Schmitt-trigger behavior to the clock
and Serial-TL inputs. Power, ground, corner, filler, ESD, and any analog pads
are intentionally outside the Chisel IO-cell mapping and must be added by the
pad-ring implementation flow.

## Tapeout Simulation

All Tapeout simulations use the PDK IO functional model and therefore require
VCS. The Makefile enables the PDK model automatically for `TapeoutConfig`:

```sh
make -C soc-generator SIM=vcs CONFIG=TapeoutConfig run-binary \
  BINARY=<binary>
```

The SPI flash/I2C EEPROM pad models are included in `TapeoutConfig`:

```sh
make -C soc-generator SIM=vcs CONFIG=TapeoutConfig \
  BINARY=<binary> run-binary
```

The automatic filelist uses `SMIC180_IO_ROOT`, which defaults to
`/data2/smic180/SP018RP_V1p0b`. It adds `verilog/SP018RP_V1p1.v` and
`+define+functional`; the latter selects the PDK's functional, non-timing
model. Gate-level timing simulation must use the signoff library and SDF/STA
settings instead. Verilator is intentionally rejected for these configurations
because the complete PDK model contains unsupported transmission-gate
primitives.
