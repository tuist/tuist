#!/usr/bin/env bash
#MISE description="Mint a fleet SSH keypair into the <fleet>-ssh Secret, so a box can be prepped before the fleet's first deploy"
#
# The operator mints this key on its first Machine reconcile — but a box must be
# prepped (which needs the pubkey) before the fleet is deployed, a chicken-and-egg
# on cold start. Pre-creating the Secret here breaks it: the operator reads the
# existing key on reconcile instead of minting its own, and prep can run first.
#
# Idempotent: if the Secret already exists it is left untouched (its private half
# is what the operator self-joins with — never clobber it).
#
# Usage:
#   mise run baremetal:mint-fleet-key tuist-tuist-dedibox-fleet
#   mise run baremetal:mint-fleet-key tuist-tuist-ovh-fleet

set -euo pipefail

fleet="${1:-}"
ns="${PREP_NAMESPACE:-tuist-staging}"

if [ -z "$fleet" ]; then
  echo "usage: mise run baremetal:mint-fleet-key <fleet-name>" >&2
  exit 2
fi

kube=(kubectl)
[ -n "${PREP_KUBE_CONTEXT:-}" ] && kube=(kubectl --context "$PREP_KUBE_CONTEXT")

if "${kube[@]}" -n "$ns" get secret "${fleet}-ssh" >/dev/null 2>&1; then
  echo "secret ${fleet}-ssh already exists in $ns — leaving it as-is"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# OpenSSH-format private key; the operator parses it with ssh.ParsePrivateKey,
# which accepts it, and the .pub is already in authorized_keys form.
ssh-keygen -t ed25519 -f "$tmp/id_ed25519" -N '' -C "$fleet" >/dev/null

"${kube[@]}" -n "$ns" create secret generic "${fleet}-ssh" \
  --from-file=id_ed25519="$tmp/id_ed25519" \
  --from-file=id_ed25519.pub="$tmp/id_ed25519.pub"
"${kube[@]}" -n "$ns" label secret "${fleet}-ssh" \
  tuist.dev/managed-by=capi-scaleway-applesilicon "tuist.dev/fleet=${fleet}" --overwrite >/dev/null

echo "✓ minted ${fleet}-ssh in $ns"
