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
  const uint8_t offset = 0x2a;
  const uint8_t expected = 0x5c;
  uint8_t data = 0;
  int rc;

  // 100 MHz peripheral clock / (5 * (249 + 1)) = 80 kHz I2C clock.
  reg_write32(I2C_PRESCALE_LO, 249);
  reg_write32(I2C_PRESCALE_HI, 0);
  reg_write32(I2C_CONTROL, I2C_CONTROL_ENABLE);

  rc = eeprom_write(offset, expected);
  if (rc != 0) {
    printf("I2C EEPROM write failed: %d\n", rc);
    return 1;
  }
  rc = eeprom_read(offset, &data);
  if (rc != 0) {
    printf("I2C EEPROM read failed: %d\n", rc);
    return 1;
  }
  if (data != expected) {
    printf("I2C EEPROM mismatch: got 0x%02x expected 0x%02x\n", data, expected);
    return 1;
  }

  printf("I2C EEPROM test passed: offset 0x%02x = 0x%02x\n", offset, data);
  return 0;
}
