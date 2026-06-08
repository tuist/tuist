#!/usr/bin/env bash
#
# Build the runtime OCI image with rules_oci, inside the Debian Bookworm dev container,
# with no Docker daemon / Buildx / QEMU. Produces:
#   1. the multi-arch index (//bazel/oci:index) — both Linux arches from this one host,
#   2. a docker-loadable tarball for the NATIVE arch (bazel-dist/kura-oci.tar) that the
#      workflow loads on the host to smoke-test and run the e2e suite against.
#
# Invoked by .github/workflows/kura-bazel.yml. SHADOW only: nothing is pushed to a
# registry. See docs/bazel-migration-plan.md (Phase 3.5).
set -euo pipefail

cd /workspace/kura

NATIVE="$(uname -m)"
case "$NATIVE" in
  x86_64) PLATFORM="//bazel/platforms:linux_x86_64" ;;
  aarch64) PLATFORM="//bazel/platforms:linux_arm64" ;;
  *) echo "unsupported native arch: $NATIVE" >&2; exit 1 ;;
esac

# Native image + tarball first, so the e2e image is ready; the index reuses the native
# arch and adds the cross arch.
echo "::group::Export native ($NATIVE) image tarball"
bazel build -c opt //bazel/oci:load --output_groups=tarball --platforms="$PLATFORM"
mkdir -p bazel-dist
cp -L bazel-bin/bazel/oci/load/tarball.tar bazel-dist/kura-oci.tar
chmod a+rw bazel-dist/kura-oci.tar
ls -l bazel-dist/kura-oci.tar
echo "::endgroup::"

echo "::group::Build multi-arch index (both arches, one host, no QEMU)"
bazel build -c opt //bazel/oci:index
echo "::endgroup::"

# ---------------------------------------------------------------------------
# TEMPORARY DIAGNOSTIC (revert after use). Compares the tikv-jemalloc-sys build
# script + its Rustc compile action KEY under the flag config (used by the linux
# job and //bazel/oci:load, which cache-hit on warm) vs the rules_oci transition
# config (//bazel/oci:index, which re-executes on warm). Also dumps executionInfo
# tags and the configuration checksum. Runs post-build so analysis is warm; never
# fails the build. See docs/bazel-migration-plan.md (OCI under-caching follow-up).
# ---------------------------------------------------------------------------
echo "::group::DIAGNOSTIC: jemalloc action keys (flag vs OCI transition)"
(
  set +e
  diag() {
    local title="$1"; shift
    echo "===DIAG=== $title"
    if ! bazel aquery -c opt "$@" --output=jsonproto >/tmp/aq.json 2>/tmp/aq.err; then
      echo "  aquery failed:"; tail -n 5 /tmp/aq.err; return
    fi
    python3 - <<'PY'
import json
d = json.load(open('/tmp/aq.json'))
tgt = {t['id']: t['label'] for t in d.get('targets', [])}
cfg = {c['id']: c for c in d.get('configuration', [])}
for a in d.get('actions', []):
    lbl = tgt.get(a.get('targetId'), '?')
    if 'jemalloc' not in lbl:
        continue
    c = cfg.get(a.get('configurationId'), {})
    print(f"  label     = {lbl}")
    print(f"  mnemonic  = {a.get('mnemonic')}")
    print(f"  actionKey = {a.get('actionKey')}")
    print(f"  execInfo  = {a.get('executionInfo', [])}")
    print(f"  config    = mnemonic={c.get('mnemonic')} isTool={c.get('isTool')} checksum={c.get('checksum')}")
    print("  ---")
PY
  }
  diag "FLAG  CargoBuildScriptRun (deps //:kura, --platforms=linux_x86_64)" --platforms=//bazel/platforms:linux_x86_64 'mnemonic("CargoBuildScriptRun", deps(//:kura))'
  diag "FLAG  Rustc               (deps //:kura, --platforms=linux_x86_64)" --platforms=//bazel/platforms:linux_x86_64 'mnemonic("Rustc", deps(//:kura))'
  diag "TRANS CargoBuildScriptRun (deps //bazel/oci:index)"                 'mnemonic("CargoBuildScriptRun", deps(//bazel/oci:index))'
  diag "TRANS Rustc               (deps //bazel/oci:index)"                 'mnemonic("Rustc", deps(//bazel/oci:index))'
) || true
echo "::endgroup::"

echo "OCI build complete."
