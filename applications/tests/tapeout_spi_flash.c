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

static void spi_delay(void)
{
  for (uint32_t i = 0; i < 512; ++i) {
    __asm__ volatile("nop");
  }
}

static int spi_write_tx(uint8_t data)
{
  for (uint32_t timeout = 0; timeout < 1000000; ++timeout) {
    if ((reg_read32(SPI_TXFIFO) & SPI_TXFIFO_FULL) == 0) {
      reg_write32(SPI_TXFIFO, data);
      return 0;
    }
  }

  return -1;
}

static int spi_read_rx(uint8_t *data)
{
  for (uint32_t timeout = 0; timeout < 1000000; ++timeout) {
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

int main(void)
{
  static const uint8_t initial_expected[] = {0xef, 0xbe, 0xad, 0xde};
  static const uint8_t write_data[] = {0x13, 0x37, 0x00, 0xff};
  uint8_t data[sizeof(write_data)];

  if (flash_read(0, data, sizeof(data)) != 0) {
    printf("SPI flash initial read timed out\n");
    return 1;
  }
  for (uint32_t i = 0; i < sizeof(data); ++i) {
    if (data[i] != initial_expected[i]) {
      printf("SPI flash initial data mismatch at %u: got 0x%02x expected 0x%02x\n",
        i, data[i], initial_expected[i]);
      return 1;
    }
  }

  if (flash_write(0x80, write_data, sizeof(write_data)) != 0 ||
      flash_read(0x80, data, sizeof(data)) != 0) {
    printf("SPI flash transfer timed out\n");
    return 1;
  }
  for (uint32_t i = 0; i < sizeof(data); ++i) {
    if (data[i] != write_data[i]) {
      printf("SPI flash write/read mismatch at %u: got 0x%02x expected 0x%02x\n",
        i, data[i], write_data[i]);
      return 1;
    }
  }

  printf("SPI flash test passed: read and write verified\n");
  return 0;
}
