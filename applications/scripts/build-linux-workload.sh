#!/usr/bin/env bash

# Build a FireMarshal Linux workload for the Chipyard/Tapeout platform. The
# default embeds the rootfs into the boot ELF because P2E has no disk device.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}/../.." rev-parse --show-toplevel)"
FIREMARSHAL_DIR="${REPO_ROOT}/applications/firemarshal"
DEFAULT_CONFIG="${REPO_ROOT}/applications/linux/workloads/poweroff.json"
CONFIG="${DEFAULT_CONFIG}"
OUTPUT_DIR="${REPO_ROOT}/applications/linux/build"
NO_DISK=1
JOBS="${FIREMARSHAL_JOBS:-}"

usage() {
  cat <<'EOF'
Usage: applications/scripts/build-linux-workload.sh [OPTIONS]

Build a FireMarshal Buildroot Linux workload for Tapeout/P2E.

Options:
  --config PATH    FireMarshal workload configuration (default: poweroff.json)
  --output DIR     Artifact root (default: applications/linux/build)
  --disk           Build a disk-backed image instead of P2E's initramfs ELF
  --jobs N         Parallel build jobs (default: FireMarshal auto-detect)
  -h, --help       Show this help text

The default output is a P2E-loadable ELF at:
  <output>/chipyard/tape-env-linux-poweroff/tape-env-linux-poweroff-bin-nodisk
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { echo "--config requires a path" >&2; exit 2; }
      CONFIG="$2"
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

if [[ -n "${JOBS}" && ! "${JOBS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "--jobs must be a positive integer: ${JOBS}" >&2
  exit 2
fi

git -C "${REPO_ROOT}" submodule update --init applications/firemarshal
if [[ ! -x "${FIREMARSHAL_DIR}/marshal" ]]; then
  echo "FireMarshal submodule is unavailable: ${FIREMARSHAL_DIR}" >&2
  exit 1
fi

# The no-disk initramfs builds FireMarshal's private BusyBox separately from
# Buildroot. Its default tc applet depends on legacy CBQ UAPI removed by the
# Tapeout toolchain headers; P2E has no network device, so disable it for this
# build and restore the upstream configuration on every exit path.
BUSYBOX_CONFIG="${FIREMARSHAL_DIR}/wlutil/busybox-config"
BUSYBOX_CONFIG_BACKUP="$(mktemp)"
BUILDROOT_DISTRO="${FIREMARSHAL_DIR}/boards/default/distros/br/br.py"
BUILDROOT_DISTRO_BACKUP="$(mktemp)"
BUILDROOT_HELPERS="${FIREMARSHAL_DIR}/boards/default/distros/br/buildroot/toolchain/helpers.mk"
BUILDROOT_HELPERS_BACKUP="$(mktemp)"
COREUTILS_MK="${FIREMARSHAL_DIR}/boards/default/distros/br/buildroot/package/coreutils/coreutils.mk"
COREUTILS_MK_BACKUP="$(mktemp)"
PROCPS_NG_MK="${FIREMARSHAL_DIR}/boards/default/distros/br/buildroot/package/procps-ng/procps-ng.mk"
PROCPS_NG_MK_BACKUP="$(mktemp)"
FAKEROOT_FS_COMMON_MK="${FIREMARSHAL_DIR}/boards/default/distros/br/buildroot/fs/common.mk"
FAKEROOT_FS_COMMON_MK_BACKUP="$(mktemp)"
cp "${BUSYBOX_CONFIG}" "${BUSYBOX_CONFIG_BACKUP}"
cp "${BUILDROOT_DISTRO}" "${BUILDROOT_DISTRO_BACKUP}"
cp "${BUILDROOT_HELPERS}" "${BUILDROOT_HELPERS_BACKUP}"
cp "${COREUTILS_MK}" "${COREUTILS_MK_BACKUP}"
cp "${PROCPS_NG_MK}" "${PROCPS_NG_MK_BACKUP}"
cp "${FAKEROOT_FS_COMMON_MK}" "${FAKEROOT_FS_COMMON_MK_BACKUP}"
restore_firemarshal_files() {
  cp "${BUSYBOX_CONFIG_BACKUP}" "${BUSYBOX_CONFIG}"
  cp "${BUILDROOT_DISTRO_BACKUP}" "${BUILDROOT_DISTRO}"
  cp "${BUILDROOT_HELPERS_BACKUP}" "${BUILDROOT_HELPERS}"
  cp "${COREUTILS_MK_BACKUP}" "${COREUTILS_MK}"
  cp "${PROCPS_NG_MK_BACKUP}" "${PROCPS_NG_MK}"
  cp "${FAKEROOT_FS_COMMON_MK_BACKUP}" "${FAKEROOT_FS_COMMON_MK}"
  rm -f "${BUSYBOX_CONFIG_BACKUP}" "${BUILDROOT_DISTRO_BACKUP}" "${BUILDROOT_HELPERS_BACKUP}" "${COREUTILS_MK_BACKUP}" "${PROCPS_NG_MK_BACKUP}" "${FAKEROOT_FS_COMMON_MK_BACKUP}"
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

# FireMarshal's Buildroot integration unconditionally fetches its pinned
# fakeroot tarball.  Reuse the local copy when it already exists so a rebuild
# is not blocked by the Debian snapshot service.
perl -0pi -e 's{        urllib\.request\.urlretrieve\(fakerootSite \+ "/" \+ fakerootTarFile, fakerootTar\)}{        if not fakerootTar.exists():\n            urllib.request.urlretrieve(fakerootSite + "/" + fakerootTarFile, fakerootTar)}' \
  "${BUILDROOT_DISTRO}"

# Buildroot 2024.05 knows GCC through 14, while the Tapeout Nix toolchain is
# GCC 15.  For a custom external toolchain, a newer compiler satisfies the
# feature floor selected by Buildroot.  Restore the upstream check on exit.
perl -0pi -e 's/if \[\[ ! "\$\$\{real_version\}\." =~ \^\$\$\{expected_version\}\\\. \]\] ; then \\\n/if [ "\$\${real_version%%.*}" -lt "\$\${expected_version}" ] ; then \\\n/' \
  "${BUILDROOT_HELPERS}"

# Coreutils 9.3's Buildroot cache assumes POSIX strerror_r(), but Nix glibc
# exposes the GNU char*-returning variant when Coreutils enables GNU APIs.
sed -i 's/ac_cv_func_strerror_r_char_p=no/ac_cv_func_strerror_r_char_p=yes/' "${COREUTILS_MK}"

# Procps 3.3.17 treats an implicit pidfd_open declaration as a usable glibc
# function. Let its existing __NR_pidfd_open fallback handle current glibc.
printf '\nPROCPS_NG_CONF_ENV += ac_cv_func_pidfd_open=no\n' >> "${PROCPS_NG_MK}"

# fakeroot preloads a host library built by Nix.  Preserve Buildroot's normal
# /bin/sh shebang, but invoke its generated script through the Nix shell so
# the preloaded library and the interpreter use the same glibc ABI.
nix_bash="$(command -v bash)"
sed -i 's|$$(HOST_DIR)/bin/fakeroot -- $$(FAKEROOT_SCRIPT)|$$(HOST_DIR)/bin/fakeroot -- '"${nix_bash}"' $$(FAKEROOT_SCRIPT)|' "${FAKEROOT_FS_COMMON_MK}"

# FireMarshal keeps Linux, OpenSBI, Buildroot, and BusyBox as nested
# submodules. This is idempotent and makes the command usable after a clone.
(
  cd "${FIREMARSHAL_DIR}"
  ./init-submodules.sh
)

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
BUILDROOT_DIR="${FIREMARSHAL_DIR}/boards/default/distros/br/buildroot"
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

COREUTILS_BUILD_DIR="${BUILDROOT_DIR}/output/build/coreutils-9.3"
if [[ -f "${COREUTILS_BUILD_DIR}/.stamp_configured" && ! -f "${COREUTILS_BUILD_DIR}/.stamp_built" ]]; then
  echo "Refreshing incomplete Buildroot coreutils configuration..."
  (
    cd "${BUILDROOT_DIR}"
    make coreutils-reconfigure
  )
fi

PROCPS_NG_BUILD_DIR="${BUILDROOT_DIR}/output/build/procps-ng-3.3.17"
if [[ -f "${PROCPS_NG_BUILD_DIR}/.stamp_configured" && ! -f "${PROCPS_NG_BUILD_DIR}/.stamp_built" ]]; then
  echo "Refreshing incomplete Buildroot procps-ng configuration..."
  (
    cd "${BUILDROOT_DIR}"
    make procps-ng-reconfigure
  )
fi

if ! command -v guestmount >/dev/null 2>&1; then
  echo "FireMarshal requires guestmount to construct the initramfs image." >&2
  echo "Install libguestfs/guestmount on this Linux host and retry." >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}" "${OUTPUT_DIR}/logs" "${OUTPUT_DIR}/run-output"

export MARSHAL_BOARD_DIR="${FIREMARSHAL_DIR}/boards/chipyard"
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
