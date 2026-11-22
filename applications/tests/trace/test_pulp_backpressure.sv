`include "rv_tracer_wrapper.sv"
// Exercise the native wrapper with a five-cycle core/ingress drain after stall.
// The scoreboard compares every accepted complete event, including sidebands.
module test_pulp_backpressure;
  logic clk=0;
  always #5 clk=~clk;
  logic rst=0, enable=0, cfg_valid=0, cfg_ready;
  logic [7:0] cfg_addr=0;
  logic [31:0] cfg_data=0;
  logic [0:0] valid=0;
  logic [0:0][3:0] itype=0;
  logic [0:0][63:0] pc=0;
  logic ready, stall;
  assign ready = !model_stall || busy == 0;
  logic [0:0] packet_valid;
  te_pkg::it_packet_type_e [0:0] packet_type;
  logic [0:0][4:0] length;
  logic [0:0][247:0] payload;
  int cycle=0, busy=0, send_index=0, stop_at=0;
  int block_events=4, accepted=0, delivered=0, stalled_events=0;
  logic [63:0] cause, tval, tvec;
  assign cause = pc[0] ^ 64'h1234;
  assign tval = pc[0] ^ 64'h5678;
  assign tvec = pc[0] ^ 64'h9abc;
  typedef struct packed {
    logic [63:0] pc;
    logic [3:0] itype;
  } expected_t;
  expected_t expected_events [512];
  bit model_stall, dense;
  rv_tracer_wrapper dut(.clk_i(clk),.rst_ni(rst),.enable_i(enable),
    .config_valid_i(cfg_valid),.config_addr_i(cfg_addr),.config_data_i(cfg_data),.config_ready_o(cfg_ready),
    .valid_i(valid),.itype_i(itype),.cause_i(cause),.tval_i(tval),.tvec_i(tvec),.epc_i(pc[0]),
    .priv_i(2'b11),.iaddr_i(pc),.iretire_i(32'd2),.ilastsize_i(1'b1),
    .encapsulator_ready_i(ready),.external_enable_i(enable),
    .packet_valid_o(packet_valid),.packet_type_o(packet_type),.packet_length_o(length),.packet_payload_o(payload),.stall_o(stall));
  always @(posedge clk) begin
    cycle<=cycle+1;
    if (busy>0) busy<=busy-1;
    if (model_stall && packet_valid && ready) busy<=length[0]+2;
    if (rst && enable && valid) begin
      expected_events[accepted] = {pc[0], itype[0]};
      accepted++;
      if (stall) stalled_events++;
    end
    if (rst && enable && dut.encoder_event.valid && dut.i_rv_tracer.encoder_ready) begin
      assert (delivered < accepted) else $fatal(1, "duplicated input event");
      assert (dut.encoder_event.iaddr[0] == expected_events[delivered].pc &&
              dut.encoder_event.itype[0] == expected_events[delivered].itype &&
              dut.encoder_event.cause == (expected_events[delivered].pc ^ 64'h1234) &&
              dut.encoder_event.tval == (expected_events[delivered].pc ^ 64'h5678) &&
              dut.encoder_event.tvec == (expected_events[delivered].pc ^ 64'h9abc) &&
              dut.encoder_event.epc == expected_events[delivered].pc &&
              dut.encoder_event.priv == 3 && dut.encoder_event.iretire[0] == 2 &&
              dut.encoder_event.ilastsize == 1)
        else $fatal(1, "input event reordered or sideband corrupted: %0d", delivered);
      delivered++;
    end
    if (packet_valid) $display("PACKET cycle=%0d type=%h len=%d payload=%h",cycle,packet_type,length[0],payload[0]);
  end
  task cfg(input logic[7:0] addr,input logic[31:0] data);
    @(negedge clk);
    while (!cfg_ready) @(negedge clk);
    cfg_valid=1;cfg_addr=addr;cfg_data=data;
    @(negedge clk);cfg_valid=0;
    repeat(5) @(negedge clk);
  endtask
  initial begin
    model_stall=$test$plusargs("stall");
    dense=$test$plusargs("dense");
    if ($value$plusargs("events=%d", block_events)) begin end
    assert (block_events >= 4 && block_events <= 128) else $fatal;
    repeat(3) @(negedge clk);rst=1;
    cfg('h16,'h80000318+4*(block_events-1));cfg('h17,0);cfg('h18,'h80000318);cfg('h19,0);cfg('h04,1);cfg('h1d,1);
    enable=1;
    // Allow enable/config Support to drain before delivering the block.
    repeat(20) @(negedge clk);
    for(int i=0;i<2000;i++) begin
      valid=0;
      if(send_index<block_events+16 && (stop_at==0 || cycle<stop_at)) begin
        valid=1;
        pc[0]=send_index<block_events ? 64'h80000318+4*send_index : 64'h80001000+4*send_index;
        itype[0]=dense ? 4'd10 : (send_index==block_events-1 ? 4'd14 : 0);
        send_index++;
      end
      @(negedge clk);
      if(model_stall) begin
        if(stall && stop_at==0) stop_at=cycle+4;
        if(!stall) stop_at=0;
      end
    end
    valid=0;
    repeat(20) @(negedge clk);
    assert (accepted == block_events+16 && delivered == accepted && dut.event_count == 0)
      else $fatal(1, "lost input event: accepted=%0d delivered=%0d queued=%0d", accepted, delivered, dut.event_count);
    assert (!model_stall || stalled_events > 0) else $fatal(1, "test never sent an event during backpressure");
    $display("BACKPRESSURE_PASS events=%0d stalled_events=%0d", delivered, stalled_events);
    $finish;
  end
endmodule
