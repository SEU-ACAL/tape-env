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
#define EEPROM_SIZE           256
#define EEPROM_PAGE_SIZE      16

#ifndef I2C_STRESS_ROUNDS
#define I2C_STRESS_ROUNDS 64
#endif

#ifndef I2C_STRESS_PROGRESS_INTERVAL
#define I2C_STRESS_PROGRESS_INTERVAL 8
#endif

#ifndef I2C_STRESS_PAGE_BYTES
#define I2C_STRESS_PAGE_BYTES EEPROM_PAGE_SIZE
#endif

#ifndef I2C_TIMEOUT_POLLS
#define I2C_TIMEOUT_POLLS 1000000U
#endif

#if I2C_STRESS_PAGE_BYTES < 1 || I2C_STRESS_PAGE_BYTES > EEPROM_PAGE_SIZE
#error "I2C_STRESS_PAGE_BYTES must be between 1 and EEPROM_PAGE_SIZE"
#endif

#if I2C_STRESS_PROGRESS_INTERVAL < 1
#error "I2C_STRESS_PROGRESS_INTERVAL must be greater than zero"
#endif

static int i2c_wait_complete(uint8_t *status_out)
{
  int saw_transfer = 0;

  for (uint32_t timeout = 0; timeout < I2C_TIMEOUT_POLLS; ++timeout) {
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

  reg_write32(I2C_COMMAND,
              I2C_COMMAND_READ | I2C_COMMAND_NACK | I2C_COMMAND_STOP);
  if (i2c_wait_complete(&status) != 0) {
    return -1;
  }

  *data = (uint8_t)reg_read32(I2C_DATA);
  return 0;
}

static int i2c_select(uint8_t address, int start)
{
  return i2c_write_byte(address,
                        (start ? I2C_COMMAND_START : 0) | I2C_COMMAND_WRITE);
}

static int eeprom_write(uint8_t offset, uint8_t data)
{
  int rc;

  rc = i2c_select(EEPROM_ADDRESS_WRITE, 1);
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
  int rc;

  rc = i2c_select(EEPROM_ADDRESS_WRITE, 1);
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

static uint8_t stress_pattern(uint32_t round, uint8_t offset)
{
  uint32_t value = 0x9e3779b9U * (round + 1U);

  value ^= (uint32_t)offset * 0x45d9f3bU;
  value ^= value >> 16;
  return (uint8_t)(value ^ (value >> 8));
}

static uint8_t page_offset(uint32_t round)
{
#ifdef I2C_STRESS_FIXED_OFFSET
  (void)round;
  return I2C_STRESS_FIXED_OFFSET;
#else
  // The multiplier is coprime to the 16 EEPROM pages, so the first 16 rounds
  // visit each page exactly once.
  return (uint8_t)(((round * 5U) & 0x0fU) * EEPROM_PAGE_SIZE);
#endif
}

int main(void)
{
  uint8_t write_data[EEPROM_PAGE_SIZE];
  uint32_t mismatches = 0;
  uint32_t transfer_errors = 0;

  reg_write32(I2C_PRESCALE_LO, 249);
  reg_write32(I2C_PRESCALE_HI, 0);
  reg_write32(I2C_CONTROL, I2C_CONTROL_ENABLE);

  printf("I2C stress: rounds=%u page_bytes=%u\n",
         (unsigned)I2C_STRESS_ROUNDS, I2C_STRESS_PAGE_BYTES);

  for (uint32_t round = 0; round < I2C_STRESS_ROUNDS; ++round) {
    uint8_t offset = page_offset(round);
    uint8_t random_offset = (uint8_t)(offset +
        ((round * 7U + 3U) % I2C_STRESS_PAGE_BYTES));
    uint8_t random_data = 0;
    int rc;

    for (uint32_t index = 0; index < I2C_STRESS_PAGE_BYTES; ++index) {
      write_data[index] = stress_pattern(round, (uint8_t)(offset + index));
    }

    printf("I2C stress write: round=%u offset=0x%02x bytes=%u\n",
           (unsigned)round, offset, I2C_STRESS_PAGE_BYTES);
    for (uint32_t index = 0; index < I2C_STRESS_PAGE_BYTES; ++index) {
      rc = eeprom_write((uint8_t)(offset + index), write_data[index]);
      if (rc != 0) {
        ++transfer_errors;
        printf("I2C stress write failed: round=%u offset=0x%02x rc=%d\n",
               (unsigned)round, (uint8_t)(offset + index), rc);
        break;
      }
    }
    if (transfer_errors != 0) {
      break;
    }

    printf("I2C stress read: round=%u offset=0x%02x bytes=%u\n",
           (unsigned)round, offset, I2C_STRESS_PAGE_BYTES);
    for (uint32_t index = 0; index < I2C_STRESS_PAGE_BYTES; ++index) {
      uint8_t read_data = 0;

      rc = eeprom_read((uint8_t)(offset + index), &read_data);
      if (rc != 0) {
        ++transfer_errors;
        printf("I2C stress read failed: round=%u offset=0x%02x rc=%d\n",
               (unsigned)round, (uint8_t)(offset + index), rc);
        break;
      }
      if (read_data != write_data[index]) {
        ++mismatches;
        printf("I2C stress mismatch: round=%u offset=0x%02x got=0x%02x expected=0x%02x\n",
               (unsigned)round, (uint8_t)(offset + index), read_data,
               write_data[index]);
      }
    }
    if (transfer_errors != 0) {
      break;
    }

    rc = eeprom_read(random_offset, &random_data);
    if (rc != 0) {
      ++transfer_errors;
      printf("I2C stress random read failed: round=%u offset=0x%02x rc=%d\n",
             (unsigned)round, random_offset, rc);
      break;
    }
    if (random_data != stress_pattern(round, random_offset)) {
      ++mismatches;
      printf("I2C stress random mismatch: round=%u offset=0x%02x got=0x%02x expected=0x%02x\n",
             (unsigned)round, random_offset, random_data,
             stress_pattern(round, random_offset));
    }

    if ((round + 1) % I2C_STRESS_PROGRESS_INTERVAL == 0 ||
        round + 1 == I2C_STRESS_ROUNDS) {
      printf("I2C stress progress: %u/%u rounds, mismatches=%u\n",
             (unsigned)(round + 1), (unsigned)I2C_STRESS_ROUNDS,
             (unsigned)mismatches);
    }
  }

  if (transfer_errors != 0 || mismatches != 0) {
    printf("I2C stress failed: transfer_errors=%u mismatches=%u\n",
           (unsigned)transfer_errors, (unsigned)mismatches);
    return 1;
  }

  printf("I2C stress passed: rounds=%u verified_bytes=%u\n",
         (unsigned)I2C_STRESS_ROUNDS,
         (unsigned)(I2C_STRESS_ROUNDS * (I2C_STRESS_PAGE_BYTES + 1)));
  return 0;
}
