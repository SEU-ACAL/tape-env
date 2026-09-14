#ifndef BBHW_TOPOLOGY_H
#define BBHW_TOPOLOGY_H
#define BB_TILE_NUM 1
#define BB_CORES_PER_TILE 1
#define BB_VIRTUAL_BANK_NUM 24
#define BB_SHARED_PHYSICAL_BANK_NUM 0
#ifndef __ASSEMBLER__
#include <stdint.h>
typedef struct { uint32_t tile; uint32_t core; } core_id_t;
static inline core_id_t bb_topology_core_id(uint32_t hart) {
  if (hart >= 1u) __builtin_trap();
  return (core_id_t){hart / 1u, hart % 1u};
}
static inline uint32_t bb_topology_core_profile(core_id_t id) {
  static const uint32_t profiles[1] = {0};
  if (id.tile >= 1u || id.core >= 1u) __builtin_trap();
  return profiles[id.core];
}
static inline uint32_t bb_topology_profile_cores_per_tile(uint32_t profile) {
  uint32_t count = 0;
  for (uint32_t core = 0; core < 1u; ++core)
    count += bb_topology_core_profile((core_id_t){0, core}) == profile;
  return count;
}
#endif
#endif
