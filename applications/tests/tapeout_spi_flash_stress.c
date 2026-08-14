#include <stdint.h>
#include <stdio.h>

#include "mmio.h"

#define SPI_BASE 0x10031000UL

#define SPI_CSMODE (SPI_BASE + 0x18)
#define SPI_FORMAT (SPI_BASE + 0x40)
#define SPI_TXFIFO (SPI_BASE + 0x48)
#define SPI_RXFIFO (SPI_BASE + 0x4c)

#define SPI_TXFIFO_FULL  0x80000000UL
#define SPI_RXFIFO_EMPTY 0x80000000UL

#define SPI_CSMODE_HOLD 2
#define SPI_CSMODE_OFF  3

#define SPI_FORMAT_RX (8U << 16)
#define SPI_FORMAT_TX ((8U << 16) | (1U << 3))

#define FLASH_CAPACITY_BYTES 0x100000U
#define FLASH_PAGE_BYTES 256U
#define STRESS_REGION_START 0x20000U
#define STRESS_REGION_BYTES 0x20000U
#define STRESS_PAGE_OFFSET  0xe0U

#ifndef SPI_FLASH_STRESS_ROUNDS
#define SPI_FLASH_STRESS_ROUNDS 64U
#endif

#ifndef SPI_FLASH_STRESS_TRANSFER_BYTES
#define SPI_FLASH_STRESS_TRANSFER_BYTES 128U
#endif

#ifndef SPI_FLASH_TIMEOUT_POLLS
#define SPI_FLASH_TIMEOUT_POLLS 1000000U
#endif

#ifndef SPI_FLASH_STRESS_PROGRESS_INTERVAL
#define SPI_FLASH_STRESS_PROGRESS_INTERVAL 8U
#endif

#if SPI_FLASH_STRESS_TRANSFER_BYTES < 1 || \
    SPI_FLASH_STRESS_TRANSFER_BYTES > FLASH_PAGE_BYTES
#error "SPI_FLASH_STRESS_TRANSFER_BYTES must be between 1 and 256"
#endif

#if SPI_FLASH_STRESS_ROUNDS < 1
#error "SPI_FLASH_STRESS_ROUNDS must be greater than zero"
#endif

#if STRESS_PAGE_OFFSET + SPI_FLASH_STRESS_TRANSFER_BYTES <= FLASH_PAGE_BYTES
#error "SPI Flash stress transfers must cross a page boundary"
#endif

#if STRESS_REGION_START + STRESS_REGION_BYTES > FLASH_CAPACITY_BYTES || \
    STRESS_REGION_BYTES <= STRESS_PAGE_OFFSET + SPI_FLASH_STRESS_TRANSFER_BYTES
#error "SPI Flash stress region must fit the simulated flash capacity"
#endif

#if SPI_FLASH_STRESS_PROGRESS_INTERVAL < 1
#error "SPI_FLASH_STRESS_PROGRESS_INTERVAL must be greater than zero"
#endif

static void spi_delay(void)
{
  for (uint32_t i = 0; i < 512; ++i) {
    __asm__ volatile("nop");
  }
}

static int spi_write_tx(uint8_t data)
{
  for (uint32_t timeout = 0; timeout < SPI_FLASH_TIMEOUT_POLLS; ++timeout) {
    if ((reg_read32(SPI_TXFIFO) & SPI_TXFIFO_FULL) == 0) {
      reg_write32(SPI_TXFIFO, data);
      return 0;
    }
  }

  return -1;
}

static int spi_read_rx(uint8_t *data)
{
  for (uint32_t timeout = 0; timeout < SPI_FLASH_TIMEOUT_POLLS; ++timeout) {
    uint32_t value = reg_read32(SPI_RXFIFO);
    if ((value & SPI_RXFIFO_EMPTY) == 0) {
      *data = (uint8_t)value;
      return 0;
    }
  }

  return -1;
}

static int spi_send_address(uint32_t address)
{
  return spi_write_tx((uint8_t)(address >> 16)) ||
         spi_write_tx((uint8_t)(address >> 8)) ||
         spi_write_tx((uint8_t)address);
}

static void spi_release_chip_select(void)
{
  spi_delay();
  reg_write32(SPI_CSMODE, SPI_CSMODE_OFF);
  spi_delay();
}

static int flash_write(uint32_t address, const uint8_t *data, uint32_t length)
{
  reg_write32(SPI_FORMAT, SPI_FORMAT_TX);
  reg_write32(SPI_CSMODE, SPI_CSMODE_HOLD);
  if (spi_write_tx(0x02) != 0 || spi_send_address(address) != 0) {
    return -1;
  }
  for (uint32_t i = 0; i < length; ++i) {
    if (spi_write_tx(data[i]) != 0) {
      return -1;
    }
  }
  spi_release_chip_select();
  return 0;
}

static int flash_read(uint32_t address, uint8_t *data, uint32_t length)
{
  reg_write32(SPI_FORMAT, SPI_FORMAT_TX);
  reg_write32(SPI_CSMODE, SPI_CSMODE_HOLD);
  if (spi_write_tx(0x03) != 0 || spi_send_address(address) != 0) {
    return -1;
  }

  spi_delay();
  reg_write32(SPI_FORMAT, SPI_FORMAT_RX);
  for (uint32_t i = 0; i < length; ++i) {
    if (spi_write_tx(0) != 0) {
      return -1;
    }
  }
  spi_delay();
  for (uint32_t i = 0; i < length; ++i) {
    if (spi_read_rx(&data[i]) != 0) {
      return -1;
    }
  }
  spi_release_chip_select();
  return 0;
}

static uint8_t stress_pattern(uint32_t round, uint32_t index)
{
  uint32_t value = 0x9e3779b9U * (round + 1U);

  value ^= 0x45d9f3bU * (index + 1U);
  value ^= value >> 16;
  value *= 0x27d4eb2dU;
  return (uint8_t)(value ^ (value >> 8) ^ (value >> 16));
}

static uint32_t stress_address(uint32_t round)
{
  const uint32_t pages =
      (STRESS_REGION_BYTES - STRESS_PAGE_OFFSET - SPI_FLASH_STRESS_TRANSFER_BYTES) /
      FLASH_PAGE_BYTES;
  const uint32_t page = (round * 17U) % pages;

  return STRESS_REGION_START + page * FLASH_PAGE_BYTES + STRESS_PAGE_OFFSET;
}

static int verify_preload_word(uint32_t address)
{
  uint8_t data[4];
  const uint32_t expected_word = 0xdeadbeefU - address;

  if (flash_read(address, data, sizeof(data)) != 0) {
    printf("SPI flash preload read timed out at 0x%06x\n", (unsigned)address);
    return -1;
  }

  for (uint32_t i = 0; i < sizeof(data); ++i) {
    const uint8_t expected = (uint8_t)(expected_word >> (i * 8U));
    if (data[i] != expected) {
      printf("SPI flash preload mismatch at 0x%06x: got=0x%02x expected=0x%02x\n",
             (unsigned)(address + i), data[i], expected);
      return -1;
    }
  }

  return 0;
}

int main(void)
{
  static const uint32_t preload_addresses[] = {0x000000U, 0x040000U, 0x0ffffcU};
  uint8_t write_data[SPI_FLASH_STRESS_TRANSFER_BYTES];
  uint8_t read_data[SPI_FLASH_STRESS_TRANSFER_BYTES];
  uint32_t mismatches = 0;
  uint32_t transfer_errors = 0;

  printf("SPI flash stress: rounds=%u transfer_bytes=%u\n",
         (unsigned)SPI_FLASH_STRESS_ROUNDS,
         (unsigned)SPI_FLASH_STRESS_TRANSFER_BYTES);

  for (uint32_t i = 0; i < sizeof(preload_addresses) / sizeof(preload_addresses[0]); ++i) {
    if (verify_preload_word(preload_addresses[i]) != 0) {
      return 1;
    }
  }

  for (uint32_t round = 0; round < SPI_FLASH_STRESS_ROUNDS; ++round) {
    const uint32_t address = stress_address(round);
    const uint32_t probe_index = (round * 29U + 7U) % SPI_FLASH_STRESS_TRANSFER_BYTES;
    uint8_t probe_data = 0;

    for (uint32_t index = 0; index < SPI_FLASH_STRESS_TRANSFER_BYTES; ++index) {
      write_data[index] = stress_pattern(round, index);
    }

    if (flash_write(address, write_data, sizeof(write_data)) != 0) {
      ++transfer_errors;
      printf("SPI flash stress write timed out: round=%u address=0x%06x bytes=%u\n",
             (unsigned)round, (unsigned)address,
             (unsigned)SPI_FLASH_STRESS_TRANSFER_BYTES);
      break;
    }

    if (flash_read(address, read_data, sizeof(read_data)) != 0) {
      ++transfer_errors;
      printf("SPI flash stress read timed out: round=%u address=0x%06x bytes=%u\n",
             (unsigned)round, (unsigned)address,
             (unsigned)SPI_FLASH_STRESS_TRANSFER_BYTES);
      break;
    }

    for (uint32_t index = 0; index < SPI_FLASH_STRESS_TRANSFER_BYTES; ++index) {
      if (read_data[index] != write_data[index]) {
        ++mismatches;
        printf("SPI flash stress mismatch: round=%u address=0x%06x index=%u got=0x%02x expected=0x%02x\n",
               (unsigned)round, (unsigned)address, (unsigned)index,
               read_data[index], write_data[index]);
      }
    }
    if (mismatches != 0) {
      break;
    }

    if (flash_read(address + probe_index, &probe_data, 1) != 0) {
      ++transfer_errors;
      printf("SPI flash stress probe timed out: round=%u address=0x%06x\n",
             (unsigned)round, (unsigned)(address + probe_index));
      break;
    }
    if (probe_data != write_data[probe_index]) {
      ++mismatches;
      printf("SPI flash stress probe mismatch: round=%u address=0x%06x got=0x%02x expected=0x%02x\n",
             (unsigned)round, (unsigned)(address + probe_index), probe_data,
             write_data[probe_index]);
      break;
    }

    if (round != 0) {
      const uint32_t previous_round = round - 1U;
      const uint32_t previous_probe_index =
          (previous_round * 29U + 7U) % SPI_FLASH_STRESS_TRANSFER_BYTES;
      const uint32_t previous_probe_address =
          stress_address(previous_round) + previous_probe_index;
      const uint8_t previous_expected =
          stress_pattern(previous_round, previous_probe_index);

      if (flash_read(previous_probe_address, &probe_data, 1) != 0) {
        ++transfer_errors;
        printf("SPI flash stress retention probe timed out: round=%u address=0x%06x\n",
               (unsigned)previous_round, (unsigned)previous_probe_address);
        break;
      }
      if (probe_data != previous_expected) {
        ++mismatches;
        printf("SPI flash stress retention mismatch: round=%u address=0x%06x got=0x%02x expected=0x%02x\n",
               (unsigned)previous_round, (unsigned)previous_probe_address,
               probe_data, previous_expected);
        break;
      }
    }

    if ((round + 1U) % SPI_FLASH_STRESS_PROGRESS_INTERVAL == 0 ||
        round + 1U == SPI_FLASH_STRESS_ROUNDS) {
      printf("SPI flash stress progress: %u/%u rounds\n",
             (unsigned)(round + 1U), (unsigned)SPI_FLASH_STRESS_ROUNDS);
    }
  }

  if (transfer_errors != 0 || mismatches != 0) {
    printf("SPI flash stress failed: transfer_errors=%u mismatches=%u\n",
           (unsigned)transfer_errors, (unsigned)mismatches);
    return 1;
  }

  printf("SPI flash stress passed: rounds=%u transfer_bytes=%u verified_bytes=%u\n",
         (unsigned)SPI_FLASH_STRESS_ROUNDS,
         (unsigned)SPI_FLASH_STRESS_TRANSFER_BYTES,
         (unsigned)(SPI_FLASH_STRESS_ROUNDS * (SPI_FLASH_STRESS_TRANSFER_BYTES + 2U) - 1U));
  return 0;
}
