#!/bin/bash
# Build script for FreeRTOS workloads

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"

echo "=== Building FreeRTOS Workloads ==="
echo "Source directory: ${SCRIPT_DIR}"
echo "Build directory: ${BUILD_DIR}"

# Check if FreeRTOS kernel submodule is initialized
if [ ! -f "${SCRIPT_DIR}/freertos-kernel/tasks.c" ]; then
    echo "ERROR: FreeRTOS kernel not found!"
    echo "Please run: cd applications/freertos-workloads && git submodule update --init --recursive"
    exit 1
fi

# Create build directory
mkdir -p "${BUILD_DIR}"

# Configure
echo ""
echo "=== Configuring CMake ==="
cmake -S "${SCRIPT_DIR}" -B "${BUILD_DIR}" -D CMAKE_BUILD_TYPE=Release

# Build
echo ""
echo "=== Building ==="
cmake --build "${BUILD_DIR}" --target all

# Show results
echo ""
echo "=== Build Complete ==="
ls -lh "${BUILD_DIR}"/*.riscv 2>/dev/null || true
echo ""
echo "Executables ready for P2E testing:"
for elf in "${BUILD_DIR}"/*.riscv; do
    if [ -f "$elf" ]; then
        echo "  - $(basename $elf)"
    fi
done
