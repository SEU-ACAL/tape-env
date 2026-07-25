#!/usr/bin/env bash

# Build a trimmed FireMarshal Linux workload for Tapeout. The default embeds
# the rootfs into the boot ELF because P2E has no disk device.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}/../.." rev-parse --show-toplevel)"
FIREMARSHAL_DIR="${REPO_ROOT}/applications/linux-workloads/firemarshal"
DEFAULT_CONFIG="${REPO_ROOT}/applications/linux-workloads/workloads/poweroff.json"
HTIF_CONSOLE_CONFIG="${REPO_ROOT}/applications/linux-workloads/workloads/htif-console.json"
FIRESIM_CONFIG="${REPO_ROOT}/applications/linux-workloads/workloads/firesim-poweroff.json"
CONFIG="${DEFAULT_CONFIG}"
CONFIG_EXPLICIT=0
OUTPUT_DIR="${REPO_ROOT}/applications/linux-workloads/build"
NO_DISK=1
VERIFY_SPIKE=0
HTIF_CONSOLE=0
FIRESIM=0
JOBS="${FIREMARSHAL_JOBS:-}"

usage() {
  cat <<'EOF'
Usage: applications/scripts/build-linux-workload.sh [OPTIONS]

Build a FireMarshal Buildroot Linux workload for Tapeout/P2E.

Options:
  --config PATH    FireMarshal workload configuration (default: poweroff.json)
  --output DIR     Artifact root (default: applications/linux-workloads/build)
  --disk           Build a disk-backed image without installing it to FireSim
  --firesim        Build and install the FireSim disk workload
  --htif-console   Build the P2E debugging workload with Linux output over HTIF
  --verify-spike   Launch the completed no-disk workload in Spike
  --jobs N         Parallel build jobs (default: FireMarshal auto-detect)
  -h, --help       Show this help text

The default output is a P2E-loadable ELF at:
  <output>/tape-env/tape-env-linux-poweroff/tape-env-linux-poweroff-bin-nodisk
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { echo "--config requires a path" >&2; exit 2; }
      CONFIG="$2"
      CONFIG_EXPLICIT=1
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a directory" >&2; exit 2; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --disk)
      NO_DISK=0
      shift
      ;;
    --htif-console)
      CONFIG="${HTIF_CONSOLE_CONFIG}"
      HTIF_CONSOLE=1
      shift
      ;;
    --firesim)
      FIRESIM=1
      NO_DISK=0
      shift
      ;;
    --verify-spike)
      VERIFY_SPIKE=1
      shift
      ;;
    --jobs)
      [[ $# -ge 2 ]] || { echo "--jobs requires a positive integer" >&2; exit 2; }
      JOBS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${FIRESIM}" -eq 1 && "${CONFIG_EXPLICIT}" -eq 0 ]]; then
  CONFIG="${FIRESIM_CONFIG}"
fi

if [[ -z "${IN_NIX_SHELL:-}" ]]; then
  echo "Run this script from the Tapeout Nix development shell:" >&2
  echo "  nix develop --command applications/scripts/build-linux-workload.sh" >&2
  exit 1
fi

if [[ "${CONFIG}" != /* ]]; then
  CONFIG="${REPO_ROOT}/${CONFIG}"
fi
if [[ "${OUTPUT_DIR}" != /* ]]; then
  OUTPUT_DIR="${REPO_ROOT}/${OUTPUT_DIR}"
fi

if [[ ! -f "${CONFIG}" ]]; then
  echo "Workload configuration does not exist: ${CONFIG}" >&2
  exit 1
fi

if [[ "${CONFIG}" == "${HTIF_CONSOLE_CONFIG}" ]]; then
  HTIF_CONSOLE=1
fi

if [[ "${FIRESIM}" -eq 1 && "${HTIF_CONSOLE}" -eq 1 ]]; then
  echo "--firesim cannot be combined with --htif-console." >&2
  exit 2
fi

# Spike places its DTB in its ROM, while the P2E OpenSBI payload deliberately
# reads the HPEC DTB from the DDR-preloaded address. Treating a Spike launch as
# a P2E HTIF validation would therefore produce a misleading boot failure.
if [[ "${HTIF_CONSOLE}" -eq 1 && "${VERIFY_SPIKE}" -eq 1 ]]; then
  echo "--verify-spike is not supported with --htif-console; run this workload through P2E DDR preload." >&2
  exit 2
fi

if [[ -n "${JOBS}" && ! "${JOBS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "--jobs must be a positive integer: ${JOBS}" >&2
  exit 2
fi

git -C "${REPO_ROOT}" submodule update --init \
  applications/linux-workloads/buildroot \
  applications/linux-workloads/busybox \
  applications/linux-workloads/iceblk-driver \
  applications/linux-workloads/icenet-driver \
  applications/linux-workloads/linux \
  applications/linux-workloads/opensbi
if [[ ! -x "${FIREMARSHAL_DIR}/marshal" ]]; then
  echo "Trimmed FireMarshal scripts are unavailable: ${FIREMARSHAL_DIR}" >&2
  exit 1
fi

# The no-disk initramfs builds FireMarshal's private BusyBox separately from
# Buildroot. Its default tc applet depends on legacy CBQ UAPI removed by the
# Tapeout toolchain headers; P2E has no network device, so disable it for this
# build and restore the upstream configuration on every exit path.
BUSYBOX_CONFIG="${FIREMARSHAL_DIR}/wlutil/busybox-config"
BUSYBOX_CONFIG_BACKUP="$(mktemp)"
BUILDROOT_DISTRO="${FIREMARSHAL_DIR}/boards/tape-env/distros/br/br.py"
BUILDROOT_DISTRO_BACKUP="$(mktemp)"
BUILDROOT_HELPERS="${FIREMARSHAL_DIR}/boards/tape-env/distros/br/buildroot/toolchain/helpers.mk"
BUILDROOT_HELPERS_BACKUP="$(mktemp)"
FAKEROOT_FS_COMMON_MK="${FIREMARSHAL_DIR}/boards/tape-env/distros/br/buildroot/fs/common.mk"
FAKEROOT_FS_COMMON_MK_BACKUP="$(mktemp)"
cp "${BUSYBOX_CONFIG}" "${BUSYBOX_CONFIG_BACKUP}"
cp "${BUILDROOT_DISTRO}" "${BUILDROOT_DISTRO_BACKUP}"
cp "${BUILDROOT_HELPERS}" "${BUILDROOT_HELPERS_BACKUP}"
cp "${FAKEROOT_FS_COMMON_MK}" "${FAKEROOT_FS_COMMON_MK_BACKUP}"
restore_firemarshal_files() {
  cp "${BUSYBOX_CONFIG_BACKUP}" "${BUSYBOX_CONFIG}"
  cp "${BUILDROOT_DISTRO_BACKUP}" "${BUILDROOT_DISTRO}"
  cp "${BUILDROOT_HELPERS_BACKUP}" "${BUILDROOT_HELPERS}"
  cp "${FAKEROOT_FS_COMMON_MK_BACKUP}" "${FAKEROOT_FS_COMMON_MK}"
  rm -f "${BUSYBOX_CONFIG_BACKUP}" "${BUILDROOT_DISTRO_BACKUP}" "${BUILDROOT_HELPERS_BACKUP}" "${FAKEROOT_FS_COMMON_MK_BACKUP}"
}
trap restore_firemarshal_files EXIT
sed -i \
  -e 's/^CONFIG_TC=y$/# CONFIG_TC is not set/' \
  -e 's/^CONFIG_FEATURE_TC_INGRESS=y$/# CONFIG_FEATURE_TC_INGRESS is not set/' \
  "${BUSYBOX_CONFIG}"

# MARSHAL_IMAGE_DIR is deliberately outside FireMarshal, so its public cache
# key is an absolute local path and cannot hit. The host cannot reach GitHub
# reliably either; skip the three futile download attempts and build locally.
sed -i \
  's/for i in range(3):/for i in range(0 if os.environ.get("FIREMARSHAL_DISABLE_PUBLIC_CACHE") else 3):/' \
  "${BUILDROOT_DISTRO}"
export FIREMARSHAL_DISABLE_PUBLIC_CACHE=1

# Older FireMarshal revisions fetch the pinned fakeroot archive unconditionally.
# Patch only that original top-level form. The local source already has the
# guarded form, and applying the replacement a second time corrupts Python
# indentation.
if grep -q '^        urllib\.request\.urlretrieve(fakerootSite + "/" + fakerootTarFile, fakerootTar)$' "${BUILDROOT_DISTRO}"; then
  perl -0pi -e 's{        urllib\.request\.urlretrieve\(fakerootSite \+ "/" \+ fakerootTarFile, fakerootTar\)}{        if not fakerootTar.exists():\n            urllib.request.urlretrieve(fakerootSite + "/" + fakerootTarFile, fakerootTar)}' \
    "${BUILDROOT_DISTRO}"
fi

# Buildroot 2024.05 knows GCC through 14, while the Tapeout Nix toolchain is
# GCC 15.  For a custom external toolchain, a newer compiler satisfies the
# feature floor selected by Buildroot.  Restore the upstream check on exit.
perl -0pi -e 's/if \[\[ ! "\$\$\{real_version\}\." =~ \^\$\$\{expected_version\}\\\. \]\] ; then \\\n/if [ "\$\${real_version%%.*}" -lt "\$\${expected_version}" ] ; then \\\n/' \
  "${BUILDROOT_HELPERS}"

# fakeroot preloads a host library built by Nix.  Preserve Buildroot's normal
# /bin/sh shebang, but invoke its generated script through the Nix shell so
# the preloaded library and the interpreter use the same glibc ABI.
nix_bash="$(command -v bash)"
sed -i 's|$$(HOST_DIR)/bin/fakeroot -- $$(FAKEROOT_SCRIPT)|$$(HOST_DIR)/bin/fakeroot -- '"${nix_bash}"' $$(FAKEROOT_SCRIPT)|' "${FAKEROOT_FS_COMMON_MK}"

if [[ -n "${FIREMARSHAL_RISCV:-}" ]]; then
  export RISCV="${FIREMARSHAL_RISCV}"
fi
if [[ -z "${RISCV:-}" || ! -x "${RISCV}/bin/riscv64-unknown-linux-gnu-gcc" ]]; then
  echo "FireMarshal requires the Linux RISC-V toolchain from nix develop." >&2
  echo "Expected: \$FIREMARSHAL_RISCV/bin/riscv64-unknown-linux-gnu-gcc" >&2
  exit 1
fi

# Buildroot's toolchain-wrapper embeds the absolute external-toolchain path.
# Reconfigure it only when nix develop has supplied a different toolchain;
# package and download caches remain intact.
BUILDROOT_DIR="${FIREMARSHAL_DIR}/boards/tape-env/distros/br/buildroot"
BUILDROOT_WRAPPER="${BUILDROOT_DIR}/output/host/bin/toolchain-wrapper"
if [[ -f "${BUILDROOT_DIR}/.config" && -x "${BUILDROOT_WRAPPER}" ]] \
  && ! grep -aFq -- "${RISCV}/bin/%s" "${BUILDROOT_WRAPPER}"; then
  echo "Refreshing Buildroot external toolchain wrapper..."
  BUILDROOT_STAGING_DIR="${BUILDROOT_DIR}/output/host/riscv64-buildroot-linux-gnu/sysroot"
  if [[ -d "${BUILDROOT_STAGING_DIR}" ]]; then
    # Buildroot preserves Nix store permissions when it copies GCC support
    # archives. Make its generated staging tree writable before reinstallation.
    chmod -R u+w "${BUILDROOT_STAGING_DIR}"
  fi
  (
    cd "${BUILDROOT_DIR}"
    make toolchain-external-custom-reconfigure
  )
fi

# Early revisions of the Nix compatibility hook changed the loader's own
# RPATH. The loader is self-relocating and must be restored from the external
# toolchain before Buildroot repackages an existing output tree.
TARGET_LOADER="${BUILDROOT_DIR}/output/target/lib/ld-linux-riscv64-lp64d.so.1"
if [[ -f "${TARGET_LOADER}" ]] && readelf -d "${TARGET_LOADER}" 2>/dev/null | grep -qE 'RPATH|RUNPATH'; then
  TOOLCHAIN_LOADER="$("${RISCV}/bin/riscv64-unknown-linux-gnu-gcc" -print-file-name=ld-linux-riscv64-lp64d.so.1)"
  if [[ ! -f "${TOOLCHAIN_LOADER}" ]]; then
    echo "Cannot restore dynamic loader from toolchain: ${TOOLCHAIN_LOADER}" >&2
    exit 1
  fi
  echo "Restoring unmodified external-toolchain dynamic loader..."
  install -m 0755 "${TOOLCHAIN_LOADER}" "${TARGET_LOADER}"
fi

if ! command -v guestmount >/dev/null 2>&1; then
  echo "FireMarshal requires guestmount to construct the initramfs image." >&2
  echo "Install libguestfs/guestmount on this Linux host and retry." >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}" "${OUTPUT_DIR}/logs" "${OUTPUT_DIR}/run-output"

export MARSHAL_BOARD_DIR="${FIREMARSHAL_DIR}/boards/tape-env"
export MARSHAL_IMAGE_DIR="${OUTPUT_DIR}"
export MARSHAL_LOG_DIR="${OUTPUT_DIR}/logs"
export MARSHAL_RES_DIR="${OUTPUT_DIR}/run-output"
export MARSHAL_MOUNT_DIR="${OUTPUT_DIR}/mount"
if [[ -n "${JOBS}" ]]; then
  export MARSHAL_JLEVEL="${JOBS}"
fi

marshal_args=(--workdir "$(dirname "${CONFIG}")")
if [[ "${NO_DISK}" -eq 1 ]]; then
  marshal_args+=(--no-disk)
fi
marshal_args+=(build "${CONFIG}")

cd "${REPO_ROOT}"
"${FIREMARSHAL_DIR}/marshal" "${marshal_args[@]}"

if [[ "${HTIF_CONSOLE}" -eq 1 ]]; then
  "${SCRIPT_DIR}/build-p2e-htif-dtb.sh" \
    --output "${OUTPUT_DIR}/tape-env/tape-env-linux-htif-console/tape-env-linux-htif-console.dtb"
fi

if [[ "${FIRESIM}" -eq 1 ]]; then
  "${FIREMARSHAL_DIR}/marshal" \
    --workdir "$(dirname "${CONFIG}")" \
    install "${CONFIG}"
fi

if [[ "${VERIFY_SPIKE}" -eq 1 ]]; then
  if [[ "${NO_DISK}" -ne 1 ]]; then
    echo "--verify-spike requires the default no-disk workload mode" >&2
    exit 2
  fi
  "${FIREMARSHAL_DIR}/marshal" \
    --workdir "$(dirname "${CONFIG}")" \
    --no-disk launch --spike "${CONFIG}"
fi
