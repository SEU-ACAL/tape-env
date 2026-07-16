#!/usr/bin/env bash

if [[ -z "${INIT_SUBMODULES_INNER:-}" ]]; then
    export INIT_SUBMODULES_INNER=1
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    RDIR=$(git rev-parse --show-toplevel)
    cd "$RDIR"

    set +e
    bash "$SCRIPT_PATH" "$@" 2>&1 | tee init-submodules.log
    status=${PIPESTATUS[0]}
    exit "$status"
fi

# Strict mode: exit on error, unset vars, and fail on pipe errors
set -euo pipefail

RDIR=$(git rev-parse --show-toplevel)

submodule_name=""

# Custom error handler function
error_handler() {
    local exit_code=$?
    local line_number=$1
    local submodule_name=$2
    echo "Error occurred at line $line_number with exit code $exit_code in \`init-submodules.sh\`."
    if [ -n "$submodule_name" ]; then
        echo "Submodule $submodule_name failed to update."
    fi
    echo "Exiting script."
    exit $exit_code
}

# Set the trap for catching errors - call the error_handler and pass in the line number on any non-zero exit status
trap 'error_handler $LINENO "$submodule_name"' ERR

function usage
{
    echo "Usage: $0 <options>"
    echo "Initialize Chipyard submodules"
    echo "By default, this will only initialize minimally required submodules"
    echo "Enable other submodules with the --full or submodule-specific flags"
    echo ""
    echo "Options:"
    echo "  -h            Display this help message"
    echo "  --full        Initialize all submodules"
    echo "  --ara         Initialize the optional ara vector-unit submodule"
    echo "  --compressacc Initialize the optional compressor accelerator submodule"
    echo "  --mempress    Initialize the optional mempress accelerator submodule"
    echo "  --saturn      Initialize the optional saturn vector-unit submodule"
    echo "  --fft         Initialize the optional FFT accelerator submodule"
    echo "  --radiance    Initialize the optional Radiance accelerator submodule"
    echo "  --gemmini     Initialize the optional Gemmini accelerator submodule"
    echo "  --nvdla       Initialize the optional NVDLA accelerator submodule"
    echo "  --cva6        Initialize the optional CVA6 core submodule"
    echo "  --sodor       Initialize the optional Sodor cores submodule"
    echo "  --ibex        Initialize the optional Ibex core submodule"
    echo "  --vexiiriscv  Initialize the optional VexiiRiscv core submodule"
    echo "  --tacit       Initialize the optional Tacit trace encoder submodule"
    echo ""
}

ENABLE_ARA=0
ENABLE_CALIPTRA=0
ENABLE_COMPRESSACC=0
ENABLE_MEMPRESS=0
ENABLE_SATURN=0
ENABLE_FFT=0
ENABLE_RADIANCE=0
ENABLE_GEMMINI=0
ENABLE_NVDLA=0
ENABLE_CVA6=0
ENABLE_SODOR=0
ENABLE_IBEX=0
ENABLE_VEXIIRISCV=0
ENABLE_TACIT=0

while test $# -gt 0
do
   case "$1" in
        -h | -H | --help | help)
            usage
            exit 1
            ;;
        --force | -f | --skip-validate) # Deprecated flags
            ;;
    	--full)
	    ENABLE_ARA=1
	    ENABLE_CALIPTRA=1
	    ENABLE_COMPRESSACC=1
	    ENABLE_MEMPRESS=1
	    ENABLE_SATURN=1
            ENABLE_CVA6=1
            ENABLE_SODOR=1
	    ENABLE_IBEX=1
    	    ENABLE_VEXIIRISCV=1
            ENABLE_FFT=1
            ENABLE_RADIANCE=1
            ENABLE_GEMMINI=1
            ENABLE_NVDLA=1
            ENABLE_TACIT=1
	    ;;
	--ara)
	    ENABLE_ARA=1
	    ;;
	--caliptra)
	    ENABLE_CALIPTRA=1
	    ;;
	--compressacc)
	    ENABLE_COMPRESSACC=1
	    ;;
	--mempress)
	    ENABLE_MEMPRESS=1
	    ;;
	--saturn)
	    ENABLE_SATURN=1
	    ;;
	--fft)
	    ENABLE_FFT=1
	    ;;
	--radiance)
	    ENABLE_RADIANCE=1
	    ;;
	--gemmini)
	    ENABLE_GEMMINI=1
	    ;;
	--nvdla)
	    ENABLE_NVDLA=1
	    ;;
	--cva6)
	    ENABLE_CVA6=1
	    ;;
    	--sodor)
    	    ENABLE_SODOR=1
    	    ;;
    	--ibex)
    	    ENABLE_IBEX=1
    	    ;;
    	--vexiiriscv)
    	    ENABLE_VEXIIRISCV=1
    	    ;;
    	--tacit)
    	    ENABLE_TACIT=1
    	    ;;
        *)
            echo "ERROR: bad argument $1"
            usage
            exit 2
            ;;
    esac
    shift
done

# check that git version is at least 1.7.8
MYGIT=$(git --version)
MYGIT=${MYGIT#'git version '} # Strip prefix
case ${MYGIT} in
    [1-9]*)
        ;;
    *)
        echo "WARNING: unknown git version"
        ;;
esac
MINGIT="1.8.5"
if [ "$MINGIT" != "$(echo -e "$MINGIT\n$MYGIT" | sort -V | head -n1)" ]; then
  echo "This script requires git version $MINGIT or greater. Exiting."
  exit 4
fi

:

set +e

cd "$RDIR"

(
    # Blocklist of submodules to initially skip:
    # - Generators with huge submodules (e.g., linux sources)
    # - FireSim until explicitly requested
    # - Hammer tool plugins
    git_submodule_exclude() {
        # Call the given subcommand (shell function) on each submodule
        # path to temporarily exclude during the recursive update
        for name in \
	    soc-generator/generator/cva6 \
            soc-generator/generator/ibex \
            soc-generator/generator/riscv-sodor \
            soc-generator/generator/vexiiriscv \
            soc-generator/generator/ara \
	    soc-generator/generator/caliptra-aes-acc \
	    soc-generator/generator/compress-acc \
            soc-generator/generator/nvdla \
	    soc-generator/generator/mempress \
            soc-generator/generator/gemmini \
            soc-generator/generator/fft-generator \
            soc-generator/generator/radiance \
            soc-generator/generator/rocket-chip \
	    soc-generator/generator/saturn \
            soc-generator/generator/tacit \
            soc-generator/sims/firesim \
            applications/nvdla-workload \
            applications/coremark \
            applications/firemarshal \
            applications/spec2017 \
            applications/zephyr \
            dependencies/tools/dsptools \
            dependencies/tools/rocket-dsp-utils \
            vlsi/hammer-mentor-plugins
        do
            "$1" "${name%/}"
        done
    }

    _skip() { git config --local "submodule.${1}.update" none ; }
    _unskip() { git config --local --unset-all "submodule.${1}.update" || : ; }

    trap 'git_submodule_exclude _unskip' EXIT INT TERM
    (
        set -x
        git_submodule_exclude _skip
        git submodule update --init --recursive || exit 1
    )
)

(
    if [[ "$ENABLE_CVA6" -eq 1 ]] ; then
        submodule_name="soc-generator/generator/cva6"
        git submodule update --init soc-generator/generator/cva6 || exit 1
        git -C soc-generator/generator/cva6 submodule update --init src/main/resources/cva6/vsrc/cva6 || exit 1
        git -C soc-generator/generator/cva6/src/main/resources/cva6/vsrc/cva6 submodule update --init src/axi || exit 1
        git -C soc-generator/generator/cva6/src/main/resources/cva6/vsrc/cva6 submodule update --init src/axi_riscv_atomics || exit 1
        git -C soc-generator/generator/cva6/src/main/resources/cva6/vsrc/cva6 submodule update --init src/common_cells || exit 1
        git -C soc-generator/generator/cva6/src/main/resources/cva6/vsrc/cva6 submodule update --init src/fpga-support || exit 1
        git -C soc-generator/generator/cva6/src/main/resources/cva6/vsrc/cva6 submodule update --init src/riscv-dbg || exit 1
        git -C soc-generator/generator/cva6/src/main/resources/cva6/vsrc/cva6 submodule update --init src/register_interface || exit 1
        git -C soc-generator/generator/cva6/src/main/resources/cva6/vsrc/cva6 submodule update --init --recursive src/fpu || exit 1
    fi

    if [[ "$ENABLE_NVDLA" -eq 1 ]] ; then
        submodule_name="soc-generator/generator/nvdla"
        git submodule update --init soc-generator/generator/nvdla || exit 1
        git -C soc-generator/generator/nvdla submodule update --init src/main/resources/hw || exit 1
    fi

    if [[ "$ENABLE_ARA" -eq 1 ]] ; then
	git submodule update --init soc-generator/generator/ara || exit 1
	git -C soc-generator/generator/ara submodule update --init ara || exit 1
    fi

    if [[ "$ENABLE_CALIPTRA" -eq 1 ]] ; then
	git submodule update --init soc-generator/generator/caliptra-aes-acc || exit 1
    fi

    if [[ "$ENABLE_FFT" -eq 1 ]] ; then
	git submodule update --init soc-generator/generator/fft-generator || exit 1
    fi

    if [[ "$ENABLE_RADIANCE" -eq 1 ]] ; then
	git submodule update --init --recursive soc-generator/generator/radiance || exit 1
    fi

    if [[ "$ENABLE_COMPRESSACC" -eq 1 ]] ; then
	git submodule update --init soc-generator/generator/compress-acc || exit 1
    fi

    if [[ "$ENABLE_MEMPRESS" -eq 1 ]] ; then
	git submodule update --init soc-generator/generator/mempress || exit 1
    fi

    if [[ "$ENABLE_SATURN" -eq 1 ]] ; then
	git submodule update --init --recursive soc-generator/generator/saturn || exit 1
    fi

    if [[ "$ENABLE_SODOR" -eq 1 ]] ; then
	git submodule update --init soc-generator/generator/riscv-sodor || exit 1
    fi

    if [[ "$ENABLE_IBEX" -eq 1 ]] ; then
	git submodule update --init --recursive soc-generator/generator/ibex || exit 1
    fi

    if [[ "$ENABLE_VEXIIRISCV" -eq 1 ]] ; then
	git submodule update --init soc-generator/generator/vexiiriscv || exit 1
        git -C soc-generator/generator/vexiiriscv submodule update --init VexiiRiscv || exit 1
        git -C soc-generator/generator/vexiiriscv/VexiiRiscv submodule update --init ext/SpinalHDL || exit 1
        git -C soc-generator/generator/vexiiriscv/VexiiRiscv submodule update --init ext/rvls || exit 1
    fi

    if [[ "$ENABLE_TACIT" -eq 1 ]] ; then
	git submodule update --init soc-generator/generator/tacit || exit 1
    fi

    if [[ "$ENABLE_GEMMINI" -eq 1 ]] ; then
        submodule_name="soc-generator/generator/gemmini"
        git submodule update --init soc-generator/generator/gemmini || exit 1
        git -C soc-generator/generator/gemmini/ submodule update --init --recursive software/gemmini-rocc-tests || exit 1
    fi

    # Non-recursive clone
    submodule_name="soc-generator/generator/rocket-chip"
    git submodule update --init soc-generator/generator/rocket-chip || exit 1

    # Minimal non-recursive clone to initialize sbt dependencies
    submodule_name="soc-generator/sims/firesim"
    git submodule update --init soc-generator/sims/firesim || exit 1
    git config --local submodule.soc-generator/sims/firesim.update none

    # Non-recursive clone
    submodule_name="dependencies/tools/rocket-dsp-utils"
    git submodule update --init dependencies/tools/rocket-dsp-utils || exit 1

    # Non-recursive clone
    submodule_name="dependencies/tools/dsptools"
    git submodule update --init dependencies/tools/dsptools || exit 1

    # Only shallow clone needed for basic SW tests
    submodule_name="applications/firemarshal"
    git submodule update --init applications/firemarshal || exit 1
)

# Configure firemarshal to know where our firesim installation is
if [ ! -f ./applications/firemarshal/marshal-config.yaml ]; then
  echo "firesim-dir: '../../soc-generator/sims/firesim/'" > ./applications/firemarshal/marshal-config.yaml
fi
