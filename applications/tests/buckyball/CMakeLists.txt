set(BB_ROOT "${CMAKE_SOURCE_DIR}/../../soc-generator/generator/buckyball/src")
set(BB_LIB "${BB_ROOT}/bb-tests/workloads/lib")

if(NOT EXISTS "${BB_LIB}/bbhw/isa/isa.h")
  message(FATAL_ERROR "Buckyball submodule missing; run ./init-submodules.sh --buckyball")
endif()

set(BB_RUNTIME
  "${CMAKE_CURRENT_SOURCE_DIR}/util.c"
  "${BB_LIB}/bbhw/mem/mem.c"
)

function(add_buckyball_test target_name source_file)
  add_executable(${target_name} ${source_file} ${BB_RUNTIME})
  target_include_directories(${target_name} PRIVATE
    "${BB_LIB}"
    "${CMAKE_CURRENT_SOURCE_DIR}"
  )
endfunction()

add_buckyball_test(bb-mvin-mvout mvin_mvout.c)
add_buckyball_test(bb-transpose-i8-16x16 transpose_i8_16x16.c)
add_buckyball_test(bb-matrix-os-4x4 matrix_os_4x4.c)

set(BB_DUMP_TARGETS bb-mvin-mvout bb-transpose-i8-16x16 bb-matrix-os-4x4 PARENT_SCOPE)
