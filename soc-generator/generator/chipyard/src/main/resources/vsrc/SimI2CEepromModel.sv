module SimI2CEepromModel #(
    parameter [6:0] I2C_ADDRESS = 7'h50
) (
    inout scl,
    inout sda,
    input reset
);

  localparam [2:0] ST_IDLE       = 3'd0;
  localparam [2:0] ST_ADDRESS    = 3'd1;
  localparam [2:0] ST_ADDR_ACK   = 3'd2;
  localparam [2:0] ST_WRITE      = 3'd3;
  localparam [2:0] ST_WRITE_ACK  = 3'd4;
  localparam [2:0] ST_READ       = 3'd5;
  localparam [2:0] ST_READ_ACK   = 3'd6;

  // I2C state changes on START, STOP, and SCL rising edges. These events are
  // mutually exclusive protocol events, despite not sharing one clock.
  /* verilator lint_off MULTIDRIVEN */
  reg [2:0] state;
  reg [7:0] shift;
  reg [2:0] bit_count;
  reg [2:0] read_bit;
  reg selected;
  reg read_transfer;
  reg expect_pointer;
  reg sda_drive_low;
  reg [7:0] memory [0:255];
  reg [7:0] memory_pointer;
  /* verilator lint_on MULTIDRIVEN */
  integer index;

  pullup(scl);
  pullup(sda);
  assign sda = sda_drive_low ? 1'b0 : 1'bz;

  initial begin
    state = ST_IDLE;
    shift = 8'h00;
    bit_count = 3'd0;
    read_bit = 3'd0;
    selected = 1'b0;
    read_transfer = 1'b0;
    expect_pointer = 1'b1;
    sda_drive_low = 1'b0;
    memory_pointer = 8'h00;
    for (index = 0; index < 256; index = index + 1) begin
      memory[index] = index[7:0];
    end
  end

  always @(posedge reset) begin
    state <= ST_IDLE;
    shift <= 8'h00;
    bit_count <= 3'd0;
    read_bit <= 3'd0;
    selected <= 1'b0;
    read_transfer <= 1'b0;
    expect_pointer <= 1'b1;
    memory_pointer <= 8'h00;
  end

  // START or repeated-START: SDA falls while SCL is released high.
  always @(negedge sda) begin
    if (!reset && (scl === 1'b1)) begin
      state <= ST_ADDRESS;
      shift <= 8'h00;
      bit_count <= 3'd0;
      selected <= 1'b0;
    end
  end

  // STOP: SDA rises while SCL is released high.
  always @(posedge sda) begin
    if (!reset && (scl === 1'b1)) begin
      state <= ST_IDLE;
      bit_count <= 3'd0;
    end
  end

  // The master and the EEPROM both sample input data on SCL rising edges.
  always @(posedge scl) begin
    if (!reset) begin
      case (state)
        ST_ADDRESS: begin
          shift <= {shift[6:0], sda};
          if (bit_count == 3'd7) begin
            selected <= (shift[6:0] == I2C_ADDRESS);
            read_transfer <= sda;
            bit_count <= 3'd0;
            state <= ST_ADDR_ACK;
          end else begin
            bit_count <= bit_count + 3'd1;
          end
        end

        ST_ADDR_ACK: begin
          if (selected) begin
            if (read_transfer) begin
              read_bit <= 3'd0;
              state <= ST_READ;
            end else begin
              expect_pointer <= 1'b1;
              state <= ST_WRITE;
            end
          end else begin
            state <= ST_IDLE;
          end
        end

        ST_WRITE: begin
          shift <= {shift[6:0], sda};
          if (bit_count == 3'd7) begin
            if (expect_pointer) begin
              memory_pointer <= {shift[6:0], sda};
              expect_pointer <= 1'b0;
            end else begin
              memory[memory_pointer] <= {shift[6:0], sda};
              memory_pointer <= memory_pointer + 8'd1;
            end
            bit_count <= 3'd0;
            state <= ST_WRITE_ACK;
          end else begin
            bit_count <= bit_count + 3'd1;
          end
        end

        ST_WRITE_ACK: state <= ST_WRITE;

        ST_READ: begin
          if (read_bit == 3'd7) begin
            read_bit <= 3'd0;
            state <= ST_READ_ACK;
          end else begin
            read_bit <= read_bit + 3'd1;
          end
        end

        ST_READ_ACK: begin
          if (sda == 1'b0) begin
            memory_pointer <= memory_pointer + 8'd1;
            read_bit <= 3'd0;
            state <= ST_READ;
          end else begin
            state <= ST_IDLE;
          end
        end

        default: begin
        end
      endcase
    end
  end

  // The EEPROM drives ACK and read data while SCL is low, before the next
  // sampling edge. It only ever drives zero, preserving I2C open-drain rules.
  always @(posedge reset or negedge scl) begin
    if (reset) begin
      sda_drive_low <= 1'b0;
    end else begin
      case (state)
        ST_ADDR_ACK:  sda_drive_low <= selected;
        ST_WRITE_ACK: sda_drive_low <= selected;
        ST_READ:      sda_drive_low <= ~memory[memory_pointer][7-read_bit];
        default:      sda_drive_low <= 1'b0;
      endcase
    end
  end

endmodule
