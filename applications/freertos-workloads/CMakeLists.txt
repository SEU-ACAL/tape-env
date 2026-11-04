########################################################################################################################
# file:  CMakeLists.txt
#
# FreeRTOS workloads for TapeoutConfig
#
# usage:
#   Build instructions:
#     cmake -S ./ -B ./build/ -D CMAKE_BUILD_TYPE=Debug
#     cmake --build ./build/ --target all
#   Cleaning:
#     cmake --build ./build/ --target clean
########################################################################################################################
cmake_minimum_required(VERSION 3.10)

project(freertos-workloads LANGUAGES C ASM)

#################################
# RISCV Toolchain
#################################

set(CMAKE_SYSTEM_NAME         "Generic" CACHE STRING "")
set(CMAKE_SYSTEM_PROCESSOR    "riscv"   CACHE STRING "")

set(TOOLCHAIN_PREFIX    "riscv64-unknown-elf-")

set(CMAKE_AR            "${TOOLCHAIN_PREFIX}ar")
set(CMAKE_ASM_COMPILER  "${TOOLCHAIN_PREFIX}gcc")
set(CMAKE_C_COMPILER    "${TOOLCHAIN_PREFIX}gcc")
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
# FreeRTOS Kernel
#################################

set(FREERTOS_KERNEL_DIR "${CMAKE_SOURCE_DIR}/freertos-kernel")

# FreeRTOS source files
set(FREERTOS_SOURCES
    ${FREERTOS_KERNEL_DIR}/tasks.c
    ${FREERTOS_KERNEL_DIR}/queue.c
    ${FREERTOS_KERNEL_DIR}/list.c
    ${FREERTOS_KERNEL_DIR}/timers.c
    ${FREERTOS_KERNEL_DIR}/event_groups.c
    ${FREERTOS_KERNEL_DIR}/stream_buffer.c
    ${FREERTOS_KERNEL_DIR}/portable/MemMang/heap_4.c
)

# FreeRTOS RISC-V port
set(FREERTOS_PORT_DIR "${FREERTOS_KERNEL_DIR}/portable/GCC/RISC-V")
set(FREERTOS_CHIP_SPECIFIC "${FREERTOS_PORT_DIR}/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions")

if(EXISTS "${FREERTOS_PORT_DIR}/port.c")
    list(APPEND FREERTOS_SOURCES
        ${CMAKE_SOURCE_DIR}/freertos_port.c
        ${FREERTOS_PORT_DIR}/portASM.S
    )
else()
    message(FATAL_ERROR "FreeRTOS RISC-V port not found at ${FREERTOS_PORT_DIR}")
endif()

# FreeRTOS include directories
include_directories(
    ${CMAKE_SOURCE_DIR}
    ${FREERTOS_KERNEL_DIR}/include
    ${FREERTOS_PORT_DIR}
    ${FREERTOS_CHIP_SPECIFIC}
)

#################################
# Build
#################################

# Test CLINT access first
add_executable(test_clint test_clint.c)

# Test simple task
add_executable(test_simple_task
    test_simple_task.c
    ${FREERTOS_SOURCES}
)

# Test busy-wait task switching
add_executable(test_busy_wait
    test_busy_wait.c
    ${FREERTOS_SOURCES}
)

# Debug test with detailed output
add_executable(test_debug
    test_debug.c
    ${FREERTOS_SOURCES}
)

# Blinky demo
add_executable(freertos_blinky
    main_blinky.c
    ${FREERTOS_SOURCES}
)

# Multi-task debug test
add_executable(test_multi_task_debug
    test_multi_task_debug.c
    ${FREERTOS_SOURCES}
)

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

add_dump_target(test_clint)
add_dump_target(test_simple_task)
add_dump_target(test_busy_wait)
add_dump_target(test_debug)
add_dump_target(freertos_blinky)
add_dump_target(test_multi_task_debug)
