#!/bin/sh

set -eu

: "${FIREMARSHAL_NIX_FAKEROOT:?missing Nix fakeroot path}"
: "${FIREMARSHAL_NIX_SH:?missing Nix shell path}"

# Buildroot invokes this executable with its generated rootfs script. Execute
# that script explicitly with Nix's shell, so libfakeroot is loaded into a
# glibc-compatible process instead of the host /bin/sh.
exec "${FIREMARSHAL_NIX_FAKEROOT}" -- "${FIREMARSHAL_NIX_SH}" "$@"
