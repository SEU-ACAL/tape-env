module SimSPIFlashPadModel #(
    parameter string PLUSARG,
    parameter bit READONLY,
    parameter longint CAPACITY_BYTES
) (
    inout sck,
    inout cs,
    inout dq_0,
    inout dq_1,
    inout dq_2,
    inout dq_3,
    input reset
);

  SimSPIFlashModel #(
      .PLUSARG(PLUSARG),
      .READONLY(READONLY),
      .CAPACITY_BYTES(CAPACITY_BYTES)
  ) flash (
      .sck(sck),
      .cs_0(cs),
      .dq_0(dq_0),
      .dq_1(dq_1),
      .dq_2(dq_2),
      .dq_3(dq_3),
      .reset(reset)
  );

endmodule
