# FireSim Archive

This directory holds the retired FireSim-specific Linux workload integration:
disk workload configuration, FireMarshal installer, and IceNIC/IceBlk driver
submodules. A standalone FireSim checkout may be retained locally under
`upstream/firesim/`; it is intentionally ignored and is not part of this
repository.
The active P2E workflow does not initialize, build, or install any of these
assets.

The archive is deliberately separate from `workloads/` and the active P2E
builder. Restoring FireSim support requires moving the required pieces back
and explicitly reintroducing its build and install path.
