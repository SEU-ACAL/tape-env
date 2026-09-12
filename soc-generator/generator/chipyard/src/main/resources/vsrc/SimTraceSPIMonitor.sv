// Simulation-only observer. It never drives the tapeout SPI pads.
module SimTraceSPIMonitor (
  inout wire sck,
  inout wire cs,
  inout wire dq_0,
  inout wire dq_1,
  inout wire dq_2,
  inout wire dq_3,
  input wire reset
);
  integer raw_fd;
  integer packet_count;
  integer reconstructed_bytes;
  integer payload_remaining;
  reg [3:0] high_nibble;
  reg have_high_nibble;
  reg waiting_magic;
  reg waiting_length;
  reg [7:0] current_byte;
  reg [7:0] length_byte;
  reg [8*1024-1:0] raw_path;

  initial begin
    raw_fd = 0;
    packet_count = 0;
    reconstructed_bytes = 0;
    payload_remaining = 0;
    high_nibble = 4'h0;
    have_high_nibble = 1'b0;
    waiting_magic = 1'b1;
    waiting_length = 1'b0;
    if ($value$plusargs("trace_spi_nibbles=%s", raw_path)) begin
      raw_fd = $fopen(raw_path, "w");
      if (raw_fd == 0) $fatal(1, "TRACE_SPI_MONITOR_FAIL cannot open %0s", raw_path);
    end
  end

  always @(posedge sck) begin
    if (reset) begin
      have_high_nibble = 1'b0;
      waiting_magic = 1'b1;
      waiting_length = 1'b0;
      payload_remaining = 0;
    end else if (!cs) begin
      if (raw_fd != 0) $fwrite(raw_fd, "%1x\n", {dq_3, dq_2, dq_1, dq_0});
      if (!have_high_nibble) begin
        high_nibble = {dq_3, dq_2, dq_1, dq_0};
        have_high_nibble = 1'b1;
      end else begin
        current_byte = {high_nibble, dq_3, dq_2, dq_1, dq_0};
        have_high_nibble = 1'b0;
        if (waiting_magic) begin
          if (current_byte == 8'ha5) begin
            waiting_magic = 1'b0;
            waiting_length = 1'b1;
          end
        end else if (waiting_length) begin
          length_byte = current_byte;
          payload_remaining = current_byte[4:0];
          waiting_length = 1'b0;
          if (current_byte[4:0] == 0) begin
            packet_count = packet_count + 1;
            reconstructed_bytes = reconstructed_bytes + 2;
            $display("TRACE_SPI_RECONSTRUCT_PASS packets=%0d bytes=%0d length=0", packet_count, reconstructed_bytes);
            waiting_magic = 1'b1;
          end
        end else begin
          payload_remaining = payload_remaining - 1;
          if (payload_remaining == 1) begin
            packet_count = packet_count + 1;
            reconstructed_bytes = reconstructed_bytes + length_byte[4:0] + 2;
            $display("TRACE_SPI_RECONSTRUCT_PASS packets=%0d bytes=%0d length=%0d", packet_count, reconstructed_bytes, length_byte[4:0]);
            waiting_magic = 1'b1;
          end
        end
      end
    end
  end

  final begin
    if (raw_fd != 0) $fclose(raw_fd);
    $display("TRACE_SPI_RECONSTRUCT_SUMMARY packets=%0d bytes=%0d", packet_count, reconstructed_bytes);
  end
endmodule
