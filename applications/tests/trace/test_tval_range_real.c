// Exercise RV64 TVAL range filtering with a nonzero high-half fault address.
#include <stdint.h>
#include <stdio.h>

#define TRACE_CTRL_BASE 0x10060000UL
#define PULP_REG_BASE   (TRACE_CTRL_BASE + 0x40)
#define PULP_REG(apb)   (PULP_REG_BASE + ((apb) * 4))

#define FAULT_ADDRESS 0x0000000100000000ULL

#ifndef TVAL_LOWER_OFFSET
#define TVAL_LOWER_OFFSET 0ULL
#endif

#ifndef TVAL_UPPER_OFFSET
#define TVAL_UPPER_OFFSET 0ULL
#endif

extern volatile uint64_t tohost;

static inline void write_reg(uint64_t addr, uint32_t value) {
  *(volatile uint32_t *)addr = value;
}

static void write_tval64(unsigned low_word, uint64_t value) {
  write_reg(PULP_REG(low_word), (uint32_t)value);
  write_reg(PULP_REG(low_word + 1), (uint32_t)(value >> 32));
}

__attribute__((naked, noreturn)) static void trap_handler(void) {
  asm volatile(
      "li t2, 10000\n"
      "1: addi t2, t2, -1\n"
      "bnez t2, 1b\n"
      "li t0, 1\n"
      "la t1, tohost\n"
      "sd t0, 0(t1)\n"
      "2: j 2b\n");
}

__attribute__((naked, noreturn)) static void user_fault(void) {
  asm volatile(
      "li t0, 1\n"
      "slli t0, t0, 32\n"
      "jr t0\n");
}

__attribute__((noreturn)) static void enter_user(void (*entry)(void)) {
  asm volatile(
      "csrw mepc, %0\n"
      "csrr t0, mstatus\n"
      "li t1, -6145\n"
      "and t0, t0, t1\n"
      "csrw mstatus, t0\n"
      "mret\n"
      :: "r"(entry) : "t0", "t1", "memory");
  __builtin_unreachable();
}

int main(void) {
  printf("TVAL_RANGE_DIAG: fault=%lx\n", (unsigned long)FAULT_ADDRESS);
  asm volatile("csrw mtvec, %0" :: "r"(trap_handler));
  asm volatile("csrw medeleg, zero" ::: "memory");
  asm volatile(
      "li t0, -1\n"
      "csrw pmpaddr0, t0\n"
      "li t0, 0x1f\n"
      "csrw pmpcfg0, t0\n"
      ::: "t0", "memory");

  // An instruction-access fault is cause 1.  The TVAL range is the only
  // varied filter; both 32-bit words are written to prove the RV64 path.
  write_reg(PULP_REG(0x07), 1);
  write_reg(PULP_REG(0x00), 3);
  write_tval64(0x0e, FAULT_ADDRESS + TVAL_UPPER_OFFSET);
  write_tval64(0x10, FAULT_ADDRESS + TVAL_LOWER_OFFSET);
  write_reg(PULP_REG(0x02), 1);  // TVAL range, enabled
  write_reg(PULP_REG(0x1d), 1);
  write_reg(PULP_REG(0x1c), 1);
  write_reg(TRACE_CTRL_BASE, 3);

  enter_user(user_fault);
}
