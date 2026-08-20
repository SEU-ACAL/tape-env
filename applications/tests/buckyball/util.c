#include "buckyball.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void init_u8_random_matrix(elem_t *matrix, int rows, int cols, int seed) {
  srand(seed);
  for (int i = 0; i < rows * cols; i++)
    matrix[i] = rand() % 128;
}

void clear_u8_matrix(elem_t *matrix, int rows, int cols) {
  memset(matrix, 0, (size_t)rows * (size_t)cols * sizeof(elem_t));
}

void clear_u32_matrix(result_t *matrix, int rows, int cols) {
  memset(matrix, 0, (size_t)rows * (size_t)cols * sizeof(result_t));
}

int compare_u8_matrices(elem_t *a, elem_t *b, int rows, int cols) {
  for (int i = 0; i < rows * cols; i++) {
    if (a[i] != b[i]) {
      printf("Mismatch at index %d: expected %d, got %d\n", i, b[i], a[i]);
      return 0;
    }
  }
  return 1;
}

int compare_u32_matrices(result_t *a, result_t *b, int rows, int cols) {
  for (int i = 0; i < rows * cols; i++) {
    if (a[i] != b[i]) {
      printf("Mismatch at index %d: expected %d, got %d\n", i, b[i], a[i]);
      return 0;
    }
  }
  return 1;
}

void transpose_u8_matrix(elem_t *src, elem_t *dst, int rows, int cols) {
  for (int i = 0; i < rows; i++)
    for (int j = 0; j < cols; j++)
      dst[j * rows + i] = src[i * cols + j];
}

void cpu_matmul(elem_t *a, elem_t *b, result_t *c, int rows, int cols,
                int inner) {
  clear_u32_matrix(c, rows, cols);
  for (int i = 0; i < rows; i++)
    for (int j = 0; j < cols; j++)
      for (int k = 0; k < inner; k++)
        c[i * cols + j] += a[i * inner + k] * b[k * cols + j];
}
