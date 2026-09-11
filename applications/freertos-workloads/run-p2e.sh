#!/bin/bash
# Script to run FreeRTOS workload on P2E with TapeoutConfig

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAPE_ENV_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
P2E_RUNNER="${TAPE_ENV_ROOT}/dependencies/p2e-runner"

# Workload to run
WORKLOAD="${1:-freertos_blinky.riscv}"
WORKLOAD_PATH="${SCRIPT_DIR}/build/${WORKLOAD}"

# Check if workload exists
if [ ! -f "${WORKLOAD_PATH}" ]; then
    echo "ERROR: Workload not found: ${WORKLOAD_PATH}"
    echo "Please build first: ./build.sh"
    exit 1
fi

echo "=== Running FreeRTOS on P2E with TapeoutConfig ==="
echo "Workload: ${WORKLOAD_PATH}"
echo "P2E Runner: ${P2E_RUNNER}"
echo ""

# Change to p2e-runner directory
cd "${P2E_RUNNER}"

# Run on P2E
echo "Starting P2E run..."
./bin/p2e run --image "${WORKLOAD_PATH}" "$@"

echo ""
echo "=== P2E Run Complete ==="
