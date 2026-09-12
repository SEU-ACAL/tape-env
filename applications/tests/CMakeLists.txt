########################################################################################################################
# file:  CMakeLists.txt
#
# usage: 
#   Edit "VARIABLES"-section to suit project requirements.
#   Build instructions:
#     cmake -S ./ -B ./build/ -D CMAKE_BUILD_TYPE=Debug
#     cmake --build ./build/ --target all
#   Cleaning:
#     cmake --build ./build/ --target clean
########################################################################################################################
cmake_minimum_required(VERSION 3.10)

project(chipyard-tests LANGUAGES C CXX)


#################################
# RISCV Toolchain
#################################

set(CMAKE_SYSTEM_NAME         "Generic" CACHE STRING "")
set(CMAKE_SYSTEM_PROCESSOR    "riscv"   CACHE STRING "")

set(TOOLCHAIN_PREFIX    "riscv64-unknown-elf-")

set(CMAKE_AR            "${TOOLCHAIN_PREFIX}ar")
set(CMAKE_ASM_COMPILER  "${TOOLCHAIN_PREFIX}gcc")
set(CMAKE_C_COMPILER    "${TOOLCHAIN_PREFIX}gcc")
set(CMAKE_CXX_COMPILER  "${TOOLCHAIN_PREFIX}g++")
set(CMAKE_LINKER        "${TOOLCHAIN_PREFIX}ld")
set(CMAKE_OBJCOPY       "${TOOLCHAIN_PREFIX}objcopy")
set(CMAKE_OBJDUMP       "${TOOLCHAIN_PREFIX}objdump")
set(CMAKE_SIZE          "${TOOLCHAIN_PREFIX}size")

set(CMAKE_EXECUTABLE_SUFFIX            ".riscv")


#################################
# Flags
#################################

# CPU architecture
set(ARCH                "rv64imafd")
set(ABI                 "lp64d")
set(CMODEL              "medany")
set(ARCH_FLAGS          -march=${ARCH} -mabi=${ABI} -mcmodel=${CMODEL})

# spec
set(SPECS               "htif_nano.specs")
set(SPEC_FLAGS          -specs=${SPECS})

# linker script
set(LINKER_SCRIPT       "htif.ld")

add_compile_options(-std=gnu99)
add_compile_options(-O2 -Wall -Wextra)
add_compile_options(-fno-common -fno-builtin-printf)
add_compile_options(${ARCH_FLAGS})
add_compile_options(${SPEC_FLAGS})

add_link_options(-static)
add_link_options(${SPEC_FLAGS})
add_link_options(-T ${LINKER_SCRIPT})


#################################
# Build
#################################

add_executable(pwm pwm.c)
add_executable(blkdev blkdev.c)
add_executable(accum accum.c)
add_executable(charcount charcount.c)
add_executable(cpp-hello cpp-hello.cpp)
add_executable(nic-loopback nic-loopback.c)
add_executable(big-blkdev big-blkdev.c)
add_executable(pingd pingd.c)
add_executable(streaming-passthrough streaming-passthrough.c)
add_executable(streaming-fir streaming-fir.c)
add_executable(nvdla nvdla.c)
add_executable(spiflashread spiflashread.c)
add_executable(spiflashwrite spiflashwrite.c)
add_executable(tapeout_i2c_stress tapeout_i2c_stress.c)
add_executable(tapeout_spi_flash tapeout_spi_flash.c)
add_executable(tapeout_spi_flash_stress tapeout_spi_flash_stress.c)
add_executable(fft fft.c)
add_executable(gcd gcd.c)
add_executable(hello hello.c)
add_executable(mt-hello mt-hello.c)
add_executable(symmetric symmetric.c)
add_executable(ctc-test ctc-test.c)
add_executable(multi-ctc-test multi-ctc-test.c)
add_executable(triple-chiplet triple-chiplet.c)
add_executable(trace_test trace/trace_test.c)
add_executable(test_lossless_stress trace/trace_test.c)
target_compile_definitions(test_lossless_stress PRIVATE TRACE_LOSSLESS=1 TRACE_SHALLOW=0 TRACE_DENSE_ITERATIONS=1024)
target_include_directories(test_lossless_stress PRIVATE ${CMAKE_SOURCE_DIR})
add_executable(test_lossless_minimal trace/test_lossless_minimal.c)
add_executable(test_lossless_minimal_notrace trace/test_lossless_minimal.c)
target_compile_definitions(test_lossless_minimal_notrace PRIVATE TEST_TRACE_ENABLE=0)
add_executable(test_lossless_minimal_notrace_diag trace/test_lossless_minimal.c)
target_compile_definitions(test_lossless_minimal_notrace_diag PRIVATE TEST_TRACE_ENABLE=0 TEST_MINIMAL_DIAGNOSTIC=1)
add_executable(test_lossless_minimal_diag trace/test_lossless_minimal.c)
target_compile_definitions(test_lossless_minimal_diag PRIVATE TEST_MINIMAL_DIAGNOSTIC=1)
add_executable(test_lossless_minimal_verified trace/test_lossless_minimal.c)
target_compile_definitions(test_lossless_minimal_verified PRIVATE TEST_MINIMAL_DIAGNOSTIC=1 DENSE_LOOP_ITERATIONS=2046UL)
add_executable(test_shallow_trace trace/trace_test.c)
target_compile_definitions(test_shallow_trace PRIVATE TRACE_LOSSLESS=1 TRACE_SHALLOW=1 TRACE_DENSE_ITERATIONS=128)
target_include_directories(test_shallow_trace PRIVATE ${CMAKE_SOURCE_DIR})
add_executable(test_shallow_trace_baseline trace/trace_test.c)
target_compile_definitions(test_shallow_trace_baseline PRIVATE TRACE_LOSSLESS=1 TRACE_SHALLOW=0 TRACE_DENSE_ITERATIONS=128)
target_include_directories(test_shallow_trace_baseline PRIVATE ${CMAKE_SOURCE_DIR})
add_executable(test_shallow_toggle trace/test_shallow_toggle.c)
target_include_directories(test_shallow_toggle PRIVATE ${CMAKE_SOURCE_DIR})
add_executable(test_time_trace trace/trace_test.c)
target_compile_definitions(test_time_trace PRIVATE TRACE_LOSSLESS=1 TRACE_SHALLOW=0 TRACE_NO_TIME=0 TRACE_DENSE_ITERATIONS=64)
target_include_directories(test_time_trace PRIVATE ${CMAKE_SOURCE_DIR})
add_executable(test_lossy_fixed trace/test_lossy_fixed.c)
add_executable(test_address_fixed trace/test_address_fixed.c)
add_executable(test_address_delta_mode trace/test_address_fixed.c)
target_compile_definitions(test_address_delta_mode PRIVATE TRACE_DELTA_ADDRESS=1u TRACE_FULL_ADDRESS=0u)
add_executable(test_address_full_mode trace/test_address_fixed.c)
target_compile_definitions(test_address_full_mode PRIVATE TRACE_DELTA_ADDRESS=0u TRACE_FULL_ADDRESS=1u)
add_executable(test_iaddr_equal_match trace/test_iaddr_filter_real.c)
target_compile_definitions(test_iaddr_equal_match PRIVATE IADDR_ENABLE_MODE=3u IADDR_MATCH_OFFSET=0u)
add_executable(test_iaddr_equal_exclude trace/test_iaddr_filter_real.c)
target_compile_definitions(test_iaddr_equal_exclude PRIVATE IADDR_ENABLE_MODE=3u IADDR_MATCH_OFFSET=2u)
add_executable(test_iaddr_range_match trace/test_iaddr_filter_real.c)
target_compile_definitions(test_iaddr_range_match PRIVATE IADDR_ENABLE_MODE=1u IADDR_LOWER_OFFSET=0u IADDR_UPPER_OFFSET=12u)
add_executable(test_iaddr_range_exclude trace/test_iaddr_filter_real.c)
target_compile_definitions(test_iaddr_range_exclude PRIVATE IADDR_ENABLE_MODE=1u IADDR_LOWER_OFFSET=2u IADDR_UPPER_OFFSET=2u)
add_executable(test_privilege_m_equal_iaddr_match trace/test_iaddr_filter_real.c)
target_compile_definitions(test_privilege_m_equal_iaddr_match PRIVATE IADDR_ENABLE_MODE=3u IADDR_MATCH_OFFSET=0u PRIV_ENABLE_MODE=3u PRIV_MATCH=3u)
add_executable(test_privilege_us_range_iaddr_exclude_m trace/test_iaddr_filter_real.c)
target_compile_definitions(test_privilege_us_range_iaddr_exclude_m PRIVATE IADDR_ENABLE_MODE=3u IADDR_MATCH_OFFSET=0u PRIV_ENABLE_MODE=1u PRIV_RANGE=4u)
add_executable(test_privilege_fixed trace/test_privilege_fixed.c)
add_executable(test_privilege_m_equal_match trace/test_privilege_filter_real.c)
target_compile_definitions(test_privilege_m_equal_match PRIVATE PRIV_ENABLE_MODE=3u PRIV_MATCH=3u)
add_executable(test_privilege_us_range_exclude_m trace/test_privilege_filter_real.c)
target_compile_definitions(test_privilege_us_range_exclude_m PRIVATE PRIV_ENABLE_MODE=1u PRIV_RANGE=4u)
add_executable(test_exception_fixed trace/test_exception_fixed.c)
add_executable(test_privilege_exception trace/test_privilege_exception.c)
add_executable(test_tval_match trace/test_exception_filter_real.c)
target_compile_definitions(test_tval_match PRIVATE TVAL_MATCH_LOW=0u)
add_executable(test_tval_exclude trace/test_exception_filter_real.c)
target_compile_definitions(test_tval_exclude PRIVATE TVAL_MATCH_LOW=1u)
add_executable(test_tval_range_high_match trace/test_tval_range_real.c)
target_compile_definitions(test_tval_range_high_match PRIVATE TVAL_LOWER_OFFSET=0ULL TVAL_UPPER_OFFSET=0ULL)
add_executable(test_tval_range_high_exclude trace/test_tval_range_real.c)
target_compile_definitions(test_tval_range_high_exclude PRIVATE TVAL_LOWER_OFFSET=4ULL TVAL_UPPER_OFFSET=8ULL)
add_executable(test_cause_equal_exclude trace/test_exception_filter_real.c)
target_compile_definitions(test_cause_equal_exclude PRIVATE CAUSE_MATCH=2u)
add_executable(test_cause_range_match trace/test_exception_filter_real.c)
target_compile_definitions(test_cause_range_match PRIVATE CAUSE_ENABLE_MODE=1u CAUSE_LOWER=8u CAUSE_UPPER=8u)
add_executable(test_cause_range_exclude trace/test_exception_filter_real.c)
target_compile_definitions(test_cause_range_exclude PRIVATE CAUSE_ENABLE_MODE=1u CAUSE_LOWER=0u CAUSE_UPPER=7u PRIV_ENABLE_MODE=3u PRIV_MATCH=0u)
add_executable(test_tvec_equal_match trace/test_exception_filter_real.c)
target_compile_definitions(test_tvec_equal_match PRIVATE TVEC_ENABLE_MODE=3u)
add_executable(test_tvec_equal_exclude trace/test_exception_filter_real.c)
target_compile_definitions(test_tvec_equal_exclude PRIVATE TVEC_ENABLE_MODE=3u TVEC_MATCH_OFFSET=4u)
add_executable(test_tvec_range_match trace/test_exception_filter_real.c)
target_compile_definitions(test_tvec_range_match PRIVATE TVEC_ENABLE_MODE=1u)
add_executable(test_tvec_range_exclude trace/test_exception_filter_real.c)
target_compile_definitions(test_tvec_range_exclude PRIVATE TVEC_ENABLE_MODE=1u TVEC_LOWER_OFFSET=4u TVEC_UPPER_OFFSET=8u)
target_include_directories(trace_test PRIVATE ${CMAKE_SOURCE_DIR})

#################################
# Buckyball (Pebble) RoCC tests
#################################

set(BB_LIB "${CMAKE_SOURCE_DIR}/../../soc-generator/generator/buckyball/src/bb-tests/workloads/lib")
if(EXISTS "${BB_LIB}/bbhw/isa/isa.h")
  add_subdirectory(buckyball)
else()
  message(STATUS "Skipping Buckyball tests (run ./init-submodules.sh --buckyball)")
  set(BB_DUMP_TARGETS)
endif()

#################################
# Disassembly
#################################

# Add a target to generate all disassemblies
add_custom_target(dump ALL)

# Function to add disassembly target for an executable
function(add_dump_target target_name)
    add_custom_target(${target_name}-dump
        BYPRODUCTS ${CMAKE_BINARY_DIR}/${target_name}.dump
        COMMAND ${CMAKE_OBJDUMP} -D $<TARGET_FILE:${target_name}> > ${CMAKE_BINARY_DIR}/${target_name}.dump
        DEPENDS ${target_name}
        COMMENT "Generating disassembly for ${target_name}"
    )
    add_dependencies(${target_name}-dump ${target_name})
    add_dependencies(dump ${target_name}-dump)
endfunction()

add_dump_target(pwm)
add_dump_target(blkdev)
add_dump_target(accum)
add_dump_target(charcount)
add_dump_target(cpp-hello)
add_dump_target(nic-loopback)
add_dump_target(big-blkdev)
add_dump_target(pingd)
add_dump_target(streaming-passthrough)
add_dump_target(streaming-fir)
add_dump_target(nvdla)
add_dump_target(spiflashread)
add_dump_target(spiflashwrite)
add_dump_target(tapeout_i2c_stress)
add_dump_target(tapeout_spi_flash)
add_dump_target(tapeout_spi_flash_stress)
add_dump_target(fft)
add_dump_target(gcd)
add_dump_target(hello)
add_dump_target(mt-hello)
add_dump_target(symmetric)
add_dump_target(ctc-test)
add_dump_target(multi-ctc-test)
add_dump_target(triple-chiplet)
foreach(bb_t ${BB_DUMP_TARGETS})
  add_dump_target(${bb_t})
endforeach()


# Add custom command to generate spiflash.img from spiflash.py
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/spiflash.img
    COMMAND python3 ${CMAKE_SOURCE_DIR}/spiflash.py --outfile ${CMAKE_SOURCE_DIR}/spiflash.img
    DEPENDS ${CMAKE_SOURCE_DIR}/spiflash.py
    COMMENT "Generating spiflash.img"
)

# Add a target for spiflash.img
add_custom_target(spiflash_img ALL
    DEPENDS ${CMAKE_BINARY_DIR}/spiflash.img
)
