#!/usr/bin/env bash

set -euo pipefail

target_root=${1:?Buildroot target directory is required}
interpreter=/lib/ld-linux-riscv64-lp64d.so.1

patchelf_bin=$(readlink -f "${FIREMARSHAL_NIX_PATCHELF:-$(command -v patchelf)}")
readelf_bin=$(readlink -f "${FIREMARSHAL_NIX_READELF:-$(command -v readelf)}")
for tool in "$patchelf_bin" "$readelf_bin"; do
  case "$tool" in
    /nix/store/*) ;;
    *)
      echo "FireMarshal post-build tool must come from Nix: $tool" >&2
      exit 1
      ;;
  esac
done

while IFS= read -r -d '' path; do
  if ! "$readelf_bin" -h "$path" 2>/dev/null | grep -q 'Machine:.*RISC-V'; then
    continue
  fi

  # Static ELF files have no dynamic section and cannot have an RPATH or
  # interpreter.  patchelf rejects them, so leave them unchanged.
  if "$readelf_bin" -d "$path" 2>/dev/null | grep -q 'Dynamic section at offset'; then
    if "$readelf_bin" -l "$path" 2>/dev/null | grep -q 'Requesting program interpreter'; then
      "$patchelf_bin" --set-interpreter "$interpreter" "$path"
    fi
    "$patchelf_bin" --remove-rpath "$path"
  fi
done < <(find "$target_root" -type f -print0)
