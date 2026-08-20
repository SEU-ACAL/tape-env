package chipyard.buckyball

import chisel3._
import chisel3.util._

import org.chipsalliance.cde.config.{Config, Parameters}
import org.chipsalliance.diplomacy.lazymodule._

import freechips.rocketchip.diplomacy.IdRange
import freechips.rocketchip.tile.{
  BuildRoCC, LazyRoCC, LazyRoCCModuleImp, OpcodeSet, RoCCCommand
}
import freechips.rocketchip.tilelink.{
  TLBuffer, TLClientNode, TLClientParameters, TLMasterPortParameters, TLWidthWidget, TLXbar, TLIdentityNode
}

import framework.system.configloader.TomlConfigLoader
import framework.system.core.accelerator.BuckyballAccelerator
import framework.system.core.rocket.RoCCCommandBB
import framework.system.tile.BarrierUnit
import framework.top.GlobalConfig

object BuckyballRoCC {
  def loadCfg(tomlPath: String): GlobalConfig = {
    val topo = TomlConfigLoader.load(tomlPath)
    require(topo.tiles.nonEmpty, s"no tiles in $tomlPath")
    require(topo.tiles.size == 1, s"RoCC attach expects 1 tile, got ${topo.tiles.size} in $tomlPath")
    val cores = topo.tiles.head.cores.flatten
    require(cores.nonEmpty, s"no Buckyball cores in $tomlPath")
    require(cores.size == 1, s"RoCC attach expects 1 Buckyball core, got ${cores.size} in $tomlPath")
    cores.head
  }

  def toBBCmd(cmd: RoCCCommand, xLen: Int): RoCCCommandBB = {
    val bb = Wire(new RoCCCommandBB(xLen))
    bb.raw_inst := 0.U
    bb.pc       := 0.U
    bb.funct    := cmd.inst.funct
    bb.funct3   := 3.U // BuckyballCommand.Custom3Funct3
    bb.rs2      := cmd.inst.rs2
    bb.rs1      := cmd.inst.rs1
    bb.xd       := cmd.inst.xd
    bb.xs1      := cmd.inst.xs1
    bb.xs2      := cmd.inst.xs2
    bb.rd       := cmd.inst.rd
    bb.opcode   := cmd.inst.opcode
    bb.rs1Data  := cmd.rs1
    bb.rs2Data  := cmd.rs2
    bb
  }
}

class BuckyballLazyRoCC(val cfg: GlobalConfig, opcodes: OpcodeSet = OpcodeSet.custom3)(implicit p: Parameters)
    extends LazyRoCC(opcodes = opcodes, nPTWPorts = 1) {

  require(!cfg.memDomain.sharedEnable,
    "BuckyballLazyRoCC only supports sharedMem.enable=false (Pebble-style)")

  val readerNode = TLClientNode(Seq(TLMasterPortParameters.v1(Seq(TLClientParameters(
    name = "bb-dma-reader",
    sourceId = IdRange(0, cfg.memDomain.dma_n_xacts)
  )))))

  val writerNode = TLClientNode(Seq(TLMasterPortParameters.v1(Seq(TLClientParameters(
    name = "bb-dma-writer",
    sourceId = IdRange(0, cfg.memDomain.dma_n_xacts)
  )))))

  val xbar = TLXbar()
  xbar := TLBuffer() := readerNode
  xbar := TLBuffer() := writerNode

  override val tlNode = TLIdentityNode()
  tlNode :=* TLWidthWidget(cfg.memDomain.dma_buswidth / 8) := TLBuffer() := xbar

  override lazy val module = new BuckyballLazyRoCCModule(this)
}

class BuckyballLazyRoCCModule(outer: BuckyballLazyRoCC) extends LazyRoCCModuleImp(outer) {
  val cfg = outer.cfg
  val xLen = cfg.core.xLen

  val (tlReader, edge) = outer.readerNode.out(0)
  val (tlWriter, _)    = outer.writerNode.out(0)

  val acc = Module(new BuckyballAccelerator(cfg)(edge))
  acc.io.hartid := 0.U
  acc.io.sfence := false.B
  acc.io.tlbExp(0).flush_skip  := false.B
  acc.io.tlbExp(0).flush_retry := false.B

  tlReader <> acc.io.tl_reader
  tlWriter <> acc.io.tl_writer

  // RoCC cmd: rocket RoCCCommand -> Buckyball RoCCCommandBB
  acc.io.cmd.valid := io.cmd.valid
  acc.io.cmd.bits  := BuckyballRoCC.toBBCmd(io.cmd.bits, xLen)
  io.cmd.ready     := acc.io.cmd.ready

  // RoCC resp: same rd/data layout
  io.resp.valid     := acc.io.resp.valid
  io.resp.bits.rd   := acc.io.resp.bits.rd
  io.resp.bits.data := acc.io.resp.bits.data
  acc.io.resp.ready := io.resp.ready

  io.busy      := acc.io.busy
  io.interrupt := acc.io.interrupt

  // Idle HellaCacheIF requestor (tile still allocates a dcache arb port)
  io.mem.req.valid          := false.B
  io.mem.req.bits           := DontCare
  io.mem.s1_kill            := false.B
  io.mem.s1_data            := DontCare
  io.mem.s2_kill            := false.B
  io.mem.keep_clock_enabled := false.B

  // PTW field wire (same mapping as BBTile.wireBBPtw)
  require(io.ptw.size == 1)
  val bbPtw = io.ptw(0)
  bbPtw.req.valid               := acc.io.ptw(0).req.valid
  bbPtw.req.bits.valid          := acc.io.ptw(0).req.bits.valid
  bbPtw.req.bits.bits.addr      := acc.io.ptw(0).req.bits.bits.addr
  bbPtw.req.bits.bits.need_gpa  := acc.io.ptw(0).req.bits.bits.need_gpa
  bbPtw.req.bits.bits.vstage1   := acc.io.ptw(0).req.bits.bits.vstage1
  bbPtw.req.bits.bits.stage2    := acc.io.ptw(0).req.bits.bits.stage2
  acc.io.ptw(0).req.ready       := bbPtw.req.ready

  acc.io.ptw(0).resp.valid                          := bbPtw.resp.valid
  acc.io.ptw(0).resp.bits.ae_ptw                    := bbPtw.resp.bits.ae_ptw
  acc.io.ptw(0).resp.bits.ae_final                  := bbPtw.resp.bits.ae_final
  acc.io.ptw(0).resp.bits.pf                        := bbPtw.resp.bits.pf
  acc.io.ptw(0).resp.bits.gf                        := bbPtw.resp.bits.gf
  acc.io.ptw(0).resp.bits.hr                        := bbPtw.resp.bits.hr
  acc.io.ptw(0).resp.bits.hw                        := bbPtw.resp.bits.hw
  acc.io.ptw(0).resp.bits.hx                        := bbPtw.resp.bits.hx
  acc.io.ptw(0).resp.bits.pte.ppn                   := bbPtw.resp.bits.pte.ppn
  acc.io.ptw(0).resp.bits.pte.reserved_for_future   := bbPtw.resp.bits.pte.reserved_for_future
  acc.io.ptw(0).resp.bits.pte.reserved_for_software := bbPtw.resp.bits.pte.reserved_for_software
  acc.io.ptw(0).resp.bits.pte.d                     := bbPtw.resp.bits.pte.d
  acc.io.ptw(0).resp.bits.pte.a                     := bbPtw.resp.bits.pte.a
  acc.io.ptw(0).resp.bits.pte.g                     := bbPtw.resp.bits.pte.g
  acc.io.ptw(0).resp.bits.pte.u                     := bbPtw.resp.bits.pte.u
  acc.io.ptw(0).resp.bits.pte.x                     := bbPtw.resp.bits.pte.x
  acc.io.ptw(0).resp.bits.pte.w                     := bbPtw.resp.bits.pte.w
  acc.io.ptw(0).resp.bits.pte.r                     := bbPtw.resp.bits.pte.r
  acc.io.ptw(0).resp.bits.pte.v                     := bbPtw.resp.bits.pte.v
  acc.io.ptw(0).resp.bits.level                     := bbPtw.resp.bits.level
  acc.io.ptw(0).resp.bits.fragmented_superpage      := bbPtw.resp.bits.fragmented_superpage
  acc.io.ptw(0).resp.bits.homogeneous               := bbPtw.resp.bits.homogeneous
  acc.io.ptw(0).resp.bits.gpa.valid                 := bbPtw.resp.bits.gpa.valid
  acc.io.ptw(0).resp.bits.gpa.bits                  := bbPtw.resp.bits.gpa.bits
  acc.io.ptw(0).resp.bits.gpa_is_pte                := bbPtw.resp.bits.gpa_is_pte

  acc.io.ptw(0).ptbr.mode  := bbPtw.ptbr.mode
  acc.io.ptw(0).ptbr.asid  := bbPtw.ptbr.asid
  acc.io.ptw(0).ptbr.ppn   := bbPtw.ptbr.ppn
  acc.io.ptw(0).hgatp.mode := bbPtw.hgatp.mode
  acc.io.ptw(0).hgatp.asid := bbPtw.hgatp.asid
  acc.io.ptw(0).hgatp.ppn  := bbPtw.hgatp.ppn
  acc.io.ptw(0).vsatp.mode := bbPtw.vsatp.mode
  acc.io.ptw(0).vsatp.asid := bbPtw.vsatp.asid
  acc.io.ptw(0).vsatp.ppn  := bbPtw.vsatp.ppn
  acc.io.ptw(0).status     := bbPtw.status
  acc.io.ptw(0).hstatus    := bbPtw.hstatus
  acc.io.ptw(0).gstatus    := bbPtw.gstatus
  acc.io.ptw(0).pmp.zipWithIndex.foreach { case (pmpPort, i) =>
    pmpPort.cfg.l   := bbPtw.pmp(i).cfg.l
    pmpPort.cfg.res := bbPtw.pmp(i).cfg.res
    pmpPort.cfg.a   := bbPtw.pmp(i).cfg.a
    pmpPort.cfg.x   := bbPtw.pmp(i).cfg.x
    pmpPort.cfg.w   := bbPtw.pmp(i).cfg.w
    pmpPort.cfg.r   := bbPtw.pmp(i).cfg.r
    pmpPort.addr    := bbPtw.pmp(i).addr
    pmpPort.mask    := bbPtw.pmp(i).mask
  }
  acc.io.ptw(0).customCSRs := DontCare
  bbPtw.customCSRs         := DontCare

  // sharedMem disabled: accept/ignore shared config path
  acc.io.shared_config.ready      := false.B
  acc.io.shared_query_group_count := 0.U
  when (acc.io.shared_config.valid) {
    assert(false.B, "Buckyball shared config emitted while sharedMem is disabled")
  }

  val barrier = Module(new BarrierUnit(1))
  barrier.io.arrive(0)   := acc.io.barrier_arrive
  acc.io.barrier_release := barrier.io.release(0)
}

/** Attach Pebble Buckyball as RoCC on a standard Rocket tile. */
class WithPebbleBuckyballRoCC(
  tomlPath: String = "generator/buckyball/examples/chips/pebble/configs/pebble.toml"
) extends Config((site, here, up) => {
  case BuildRoCC =>
    val cfg = BuckyballRoCC.loadCfg(tomlPath)
    up(BuildRoCC) ++ Seq((p: Parameters) => {
      implicit val q = p
      LazyModule(new BuckyballLazyRoCC(cfg))
    })
})
