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
    echo "Enable the full checkout or optional Gemmini, Linux workload, and P2E sources"
    echo ""
    echo "Options:"
    echo "  -h            Display this help message"
    echo "  --full        Initialize all submodules"
    echo "  --gemmini     Initialize the optional Gemmini accelerator submodule"
    echo "  --linux       Initialize Linux workload build dependencies"
    echo "  --p2e         Initialize the optional P2E runner submodule"
    echo ""
}

ENABLE_FULL=0
ENABLE_GEMMINI=0
ENABLE_LINUX=0
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
        --linux|--firemarshal)
            ENABLE_LINUX=1
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

init_linux_workloads() {
    local linux_submodules=(
        applications/linux-workloads/buildroot
    )
    submodule_name="Linux workload Buildroot"
    git submodule update --init "${linux_submodules[@]}"
}

# Keep the focused optional initialization from updating unrelated generator
# submodules in an existing workspace.
if [[ "$ENABLE_LINUX" -eq 1 && "$ENABLE_FULL" -eq 0 && "$ENABLE_GEMMINI" -eq 0 && "$ENABLE_P2E" -eq 0 ]]; then
    init_linux_workloads
    exit 0
fi

# Keep a P2E-only checkout independent from the default recursive update.
if [[ "$ENABLE_P2E" -eq 1 && "$ENABLE_FULL" -eq 0 && "$ENABLE_GEMMINI" -eq 0 && "$ENABLE_LINUX" -eq 0 ]]; then
    update_submodule dependencies/p2e-runner
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
        applications/linux-workloads/buildroot
        dependencies/p2e-runner
    )

    # Git reads submodule.<name>.update using the section name from
    # .gitmodules, which is not necessarily the checkout path. In particular,
    # the Linux workload submodules use applications_linux_* names.
    submodule_name_for_path() {
        local path="$1"
        local name
        name="$(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | \
            awk -v path="$path" '$2 == path { name = $1; sub(/^submodule\./, "", name); sub(/\.path$/, "", name); print name; exit }')"
        if [[ -z "$name" ]]; then
            echo "No submodule name registered for path: $path" >&2
            return 1
        fi
        echo "$name"
    }

    skip_submodule() {
        local name
        name="$(submodule_name_for_path "$1")"
        git config --local "submodule.$name.update" none
    }

    unskip_submodule() {
        local name
        name="$(submodule_name_for_path "$1")"
        git config --local --unset-all "submodule.$name.update" || :
    }

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

    if [[ "$ENABLE_LINUX" -eq 1 ]]; then
        init_linux_workloads
    fi

    if [[ "$ENABLE_P2E" -eq 1 ]]; then
        echo "P2E INIT"
        update_submodule dependencies/p2e-runner
    fi
fi
