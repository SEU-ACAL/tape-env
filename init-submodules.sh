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
    echo "Enable the full checkout or optional Gemmini, FireMarshal, and P2E sources"
    echo ""
    echo "Options:"
    echo "  -h            Display this help message"
    echo "  --full        Initialize all submodules"
    echo "  --gemmini     Initialize the optional Gemmini accelerator submodule"
    echo "  --firemarshal Initialize FireMarshal and its Linux workload dependencies"
    echo "  --p2e         Initialize the optional P2E runner submodule"
    echo ""
}

ENABLE_FULL=0
ENABLE_GEMMINI=0
ENABLE_FIREMARSHAL=0
ENABLE_P2E=0

while test $# -gt 0
do
   case "$1" in
        -h | -H | --help | help)
            usage
            exit 0
            ;;
        --force | -f | --skip-validate) # Deprecated flags
            ;;
    	--full)
            ENABLE_FULL=1
            ;;
	--gemmini)
	    ENABLE_GEMMINI=1
	    ;;
        --firemarshal)
            ENABLE_FIREMARSHAL=1
            ;;
        --p2e)
            ENABLE_P2E=1
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

cd "$RDIR"

# Keep cached checkouts aligned with URLs changed in .gitmodules, including
# HTTPS-only CI environments where SSH to GitHub is unavailable.
git submodule sync --recursive

update_submodule() {
    submodule_name="$1"
    if [[ "${2:-}" == "recursive" ]]; then
        git submodule update --init --recursive "$submodule_name"
    else
        git submodule update --init "$submodule_name"
    fi
}

init_firemarshal() {
    update_submodule applications/firemarshal
    submodule_name="applications/firemarshal Linux workload dependencies"
    (
        cd applications/firemarshal
        ./init-submodules.sh
    )
}

# FireMarshal is self-contained. Keep the focused optional initialization from
# updating unrelated Chipyard generator submodules in an existing workspace.
if [[ "$ENABLE_FIREMARSHAL" -eq 1 && "$ENABLE_FULL" -eq 0 && "$ENABLE_GEMMINI" -eq 0 && "$ENABLE_P2E" -eq 0 ]]; then
    init_firemarshal
    exit 0
fi

if [[ "$ENABLE_FULL" -eq 1 ]]; then
    submodule_name="all registered submodules"
    git submodule update --init --recursive
else
    excluded_submodules=(
        soc-generator/generator/gemmini
        soc-generator/generator/rocket-chip
        applications/zephyr
        applications/firemarshal
        dependencies/p2e-runner
    )

    skip_submodule() { git config --local "submodule.$1.update" none; }
    unskip_submodule() { git config --local --unset-all "submodule.$1.update" || :; }

    (
        trap 'for path in "${excluded_submodules[@]}"; do unskip_submodule "$path"; done' EXIT INT TERM
        for path in "${excluded_submodules[@]}"; do
            skip_submodule "$path"
        done
        git submodule update --init --recursive
    )

    update_submodule soc-generator/generator/rocket-chip

    if [[ "$ENABLE_GEMMINI" -eq 1 ]]; then
        update_submodule soc-generator/generator/gemmini
        submodule_name="soc-generator/generator/gemmini/software/gemmini-rocc-tests"
        git -C soc-generator/generator/gemmini submodule update --init --recursive software/gemmini-rocc-tests
    fi

    if [[ "$ENABLE_FIREMARSHAL" -eq 1 ]]; then
        init_firemarshal
    fi

    if [[ "$ENABLE_P2E" -eq 1 ]]; then
        update_submodule dependencies/p2e-runner
    fi
fi
