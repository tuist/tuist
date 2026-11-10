#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep the binary under the checkout: runner and DinD share the work directory.
scratch=$(mktemp -d "$PWD/.cache-volume-test.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
GOOS=linux go test -c -o "$scratch/volume.test" github.com/tuist/tuist/infra/runner-cache
docker run --rm --privileged -v "$scratch/volume.test:/volume.test:ro" -v "$PWD/scripts:/scripts:ro" ubuntu:24.04 bash -ceu '
  apt-get update -qq
  apt-get install -y -qq xfsprogs e2fsprogs util-linux git git-lfs ca-certificates >/tmp/install.log
  bash /scripts/provision-cache-filesystem_test.sh
  truncate -s 4G /tmp/cache-filesystem.img
  mkfs.xfs -q -m reflink=1 /tmp/cache-filesystem.img
  mkdir /cache
  mount -o loop /tmp/cache-filesystem.img /cache
  trap "umount /cache" EXIT
  CACHE_VOLUME_E2E_ROOT=/cache /volume.test -test.run TestLinuxLocalImages -test.v -test.timeout 5m
  # A real checkout master from a public LFS repository, in ext4 images on the
  # reflink filesystem, exercised the way a job and actions/checkout use it.
  TUIST_CHECKOUT_E2E=1 TUIST_CHECKOUT_E2E_ROOT=/cache /volume.test -test.run TestCheckoutMasterEndToEnd -test.v -test.timeout 10m
'
