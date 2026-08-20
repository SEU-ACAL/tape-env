#include "buckyball.h"
#include <bbhw/isa/isa.h>
#include <bbhw/mem/mem.h>
#include <stdio.h>

#define DIM 16

static elem_t input_matrix[DIM * DIM] __attribute__((aligned(128)));
static elem_t output_matrix[DIM * DIM] __attribute__((aligned(128)));

static int mvin_mvout_simple_test(void) {
  uint32_t bank_id = 0;
  bb_mem_alloc(bank_id, 1, 1);

  init_u8_random_matrix(input_matrix, DIM, DIM, 111);
  bb_mvin((uintptr_t)input_matrix, bank_id, DIM, 1);
  clear_u8_matrix(output_matrix, DIM, DIM);
  bb_mvout((uintptr_t)output_matrix, bank_id, DIM, 1);
  bb_fence();

  if (!compare_u8_matrices(output_matrix, input_matrix, DIM, DIM)) {
    printf("Test mvin/mvout simple FAILED\n");
    return 0;
  }
  printf("Test mvin/mvout simple PASSED\n");
  return 1;
}

int main(void) {
  if (!mvin_mvout_simple_test()) {
    printf("mvin/mvout simple test FAILED\n");
    return 1;
  }
  printf("mvin/mvout simple test PASSED\n");
  return 0;
}
