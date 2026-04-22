#!/usr/bin/env bash
#MISE description="Build, sign, and zip the Tuist Grafana app plugin for upload to grafana.com or a private Grafana stack"
#USAGE flag "--skip-sign" help="Produce an unsigned zip (only loadable with GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS)"
#USAGE flag "--root-urls <urls>" help="Comma-separated root URLs to sign for. Required for private plugins."
#USAGE flag "--signature-type <type>" help="Signature type: private, community, or commercial. Defaults to private."
set -euo pipefail

PLUGIN_DIR="${MISE_PROJECT_ROOT}"
cd "${PLUGIN_DIR}"

# Prepend the plugin's pinned node + pnpm to PATH so we don't pick up nvm
# or system installs. The `.config/` webpack scaffold assumes Node >=22.
NODE_BIN_DIR="$(dirname "$(mise which node)")"
PNPM_BIN_DIR="$(dirname "$(mise which pnpm)")"
export PATH="${NODE_BIN_DIR}:${PNPM_BIN_DIR}:${PATH}"

node --version | grep -qE '^v(2[4-9]|[3-9][0-9])' || {
  echo "ERROR: expected Node >=24 from mise (got $(node --version))." >&2
  echo "       Check grafana/mise.toml and run 'mise install -C grafana'." >&2
  exit 1
}

PLUGIN_ID="$(jq -r .id src/plugin.json)"
PLUGIN_VERSION="$(jq -r .version package.json)"
ARTIFACT="${PLUGIN_DIR}/${PLUGIN_ID}-${PLUGIN_VERSION}.zip"

# --- Install + build ---------------------------------------------------------
# `--ignore-workspace` stops pnpm from attaching the plugin to the repo-root
# pnpm-workspace.yaml; the plugin has its own lockfile and dependency tree.
echo "==> Installing dependencies (pnpm, ignoring repo workspace)"
pnpm install --ignore-workspace --prefer-offline

echo "==> Building (webpack, production mode)"
# Force ts-node's transpile-only mode so the webpack config .ts files don't
# fail on missing upstream plugin typings (they're real, but not worth
# blocking the build on).
TS_NODE_TRANSPILE_ONLY=true TS_NODE_FILES=true \
  pnpm run build

# --- Sign --------------------------------------------------------------------
if [ "${usage_skip_sign:-false}" = "true" ]; then
  echo "==> Skipping signing (--skip-sign). The zip will only load when Grafana is"
  echo "    started with GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=${PLUGIN_ID}."
else
  if [ -z "${GRAFANA_ACCESS_POLICY_TOKEN:-}" ]; then
    echo "ERROR: GRAFANA_ACCESS_POLICY_TOKEN is not set." >&2
    echo "       Mint one at https://grafana.com/orgs/tuist/access-policies and export it," >&2
    echo "       or pass --skip-sign to produce an unsigned build for local Grafana dev." >&2
    exit 1
  fi

  sig_type="${usage_signature_type:-private}"
  sign_args=(--signatureType "${sig_type}")
  if [ -n "${usage_root_urls:-}" ]; then
    sign_args+=(--rootUrls "${usage_root_urls}")
  elif [ "${sig_type}" = "private" ]; then
    echo "ERROR: private signatures require --root-urls <comma-separated urls>." >&2
    echo "       Example: --root-urls https://acme.grafana.net/" >&2
    exit 1
  fi

  echo "==> Signing (${sig_type})"
  pnpm dlx @grafana/sign-plugin@latest "${sign_args[@]}"
fi

# --- Zip ---------------------------------------------------------------------
echo "==> Packaging ${ARTIFACT}"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

cp -R dist "${STAGE}/${PLUGIN_ID}"
rm -f "${ARTIFACT}"
(cd "${STAGE}" && zip -r "${ARTIFACT}" "${PLUGIN_ID}" > /dev/null)

echo
echo "Wrote ${ARTIFACT}"
echo "SHA-256: $(shasum -a 256 "${ARTIFACT}" | awk '{print $1}')"
echo "Size:    $(du -h "${ARTIFACT}" | awk '{print $1}')"
