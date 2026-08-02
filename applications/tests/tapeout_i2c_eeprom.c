#include <stdint.h>
#include <stdio.h>

#include "mmio.h"

#define I2C_BASE 0x10040000UL

#define I2C_PRESCALE_LO (I2C_BASE + 0x00)
#define I2C_PRESCALE_HI (I2C_BASE + 0x04)
#define I2C_CONTROL     (I2C_BASE + 0x08)
#define I2C_DATA        (I2C_BASE + 0x0c)
#define I2C_COMMAND     (I2C_BASE + 0x10)

#define I2C_CONTROL_ENABLE 0x80
#define I2C_COMMAND_START  0x80
#define I2C_COMMAND_STOP   0x40
#define I2C_COMMAND_READ   0x20
#define I2C_COMMAND_WRITE  0x10
#define I2C_COMMAND_NACK   0x08

#define I2C_STATUS_RXACK 0x80
#define I2C_STATUS_TIP   0x02

#define EEPROM_ADDRESS_WRITE 0xa0
#define EEPROM_ADDRESS_READ  0xa1

static int i2c_wait_complete(uint8_t *status_out)
{
  int saw_transfer = 0;

  for (uint32_t timeout = 0; timeout < 1000000; ++timeout) {
    uint8_t status = (uint8_t)reg_read32(I2C_COMMAND);
    if ((status & I2C_STATUS_TIP) != 0) {
      saw_transfer = 1;
    } else if (saw_transfer) {
      *status_out = status;
      return 0;
    }
  }

  return -1;
}

static int i2c_write_byte(uint8_t data, uint8_t command)
{
  uint8_t status;

  reg_write32(I2C_DATA, data);
  reg_write32(I2C_COMMAND, command);
  if (i2c_wait_complete(&status) != 0) {
    return -1;
  }

  return (status & I2C_STATUS_RXACK) != 0 ? -2 : 0;
}

static int i2c_read_byte(uint8_t *data)
{
  uint8_t status;

  reg_write32(I2C_COMMAND, I2C_COMMAND_READ | I2C_COMMAND_NACK | I2C_COMMAND_STOP);
  if (i2c_wait_complete(&status) != 0) {
    return -1;
  }

  *data = (uint8_t)reg_read32(I2C_DATA);
  return 0;
}

static int i2c_select(uint8_t address, uint8_t start)
{
  return i2c_write_byte(address, (start ? I2C_COMMAND_START : 0) | I2C_COMMAND_WRITE);
}

static int eeprom_write(uint8_t offset, uint8_t data)
{
  int rc = i2c_select(EEPROM_ADDRESS_WRITE, 1);
  if (rc != 0) {
    return rc;
  }
  rc = i2c_write_byte(offset, I2C_COMMAND_WRITE);
  if (rc != 0) {
    return rc;
  }
  return i2c_write_byte(data, I2C_COMMAND_WRITE | I2C_COMMAND_STOP);
}

static int eeprom_read(uint8_t offset, uint8_t *data)
{
  int rc = i2c_select(EEPROM_ADDRESS_WRITE, 1);
  if (rc != 0) {
    return rc;
  }
  rc = i2c_write_byte(offset, I2C_COMMAND_WRITE);
  if (rc != 0) {
    return rc;
  }
  rc = i2c_select(EEPROM_ADDRESS_READ, 1);
  if (rc != 0) {
    return rc;
  }
  return i2c_read_byte(data);
}

int main(void)
{
  // 目标：向 EEPROM 内部地址 0x2a 写入 0x5c，并随机读回验证。
  const uint8_t offset = 0x2a;
  const uint8_t expected = 0x5c;
  uint8_t data = 0;
  int rc;

  // 配置并使能 I2C 控制器。波形中之后的 SCL 有效周期约为 10.71 us。
  reg_write32(I2C_PRESCALE_LO, 249);
  reg_write32(I2C_PRESCALE_HI, 0);
  reg_write32(I2C_CONTROL, I2C_CONTROL_ENABLE);

  // 写事务：S -> 0xa0 -> ACK -> 0x2a -> ACK -> 0x5c -> ACK -> P。
  // 本次 FSDB 中该事务从 3.076415 ms 的 START 开始，3.383945 ms STOP；
  // EEPROM 在 3.357525 ms 将 memory[0x2a] 从初始值 0x2a 改为 0x5c。
  rc = eeprom_write(offset, expected);
  if (rc != 0) {
    printf("I2C EEPROM write failed: %d\n", rc);
    return 1;
  }
  // 随机读事务：S -> 0xa0 -> ACK -> 0x2a -> ACK -> Sr -> 0xa1 -> ACK
  //             -> 0x5c -> NACK -> P。
  // 先以写方向设置 EEPROM 的内部地址指针，再用 repeated-START 切换至读
  // 方向；FSDB 中 repeated-START 位于 3.602575 ms，读出的 0x5c 位于
  // 3.714695--3.789705 ms，最后于 3.816125 ms 产生 STOP。
  rc = eeprom_read(offset, &data);
  if (rc != 0) {
    printf("I2C EEPROM read failed: %d\n", rc);
    return 1;
  }
  // 软件比较接收寄存器中的读值与写入值，确认完整的 I2C 写/读路径正确。
  if (data != expected) {
    printf("I2C EEPROM mismatch: got 0x%02x expected 0x%02x\n", data, expected);
    return 1;
  }

  printf("I2C EEPROM test passed: offset 0x%02x = 0x%02x\n", offset, data);
  return 0;
}
