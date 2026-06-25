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

# sudo-password: the login password the install sets, which the self-join uses
# once to establish NOPASSWD sudo. 14-char alphanumeric (the Dedibox install API
# caps passwords at 15 and rejects symbols).
sudopw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 14)"

if "${kube[@]}" -n "$ns" get secret "${fleet}-ssh" >/dev/null 2>&1; then
  if "${kube[@]}" -n "$ns" get secret "${fleet}-ssh" -o jsonpath='{.data.sudo-password}' 2>/dev/null | grep -q .; then
    echo "secret ${fleet}-ssh already complete in $ns — leaving it as-is"
  else
    # Backfill sudo-password into a key minted before this field existed.
    "${kube[@]}" -n "$ns" patch secret "${fleet}-ssh" -p "{\"data\":{\"sudo-password\":\"$(printf %s "$sudopw" | base64)\"}}"
    echo "✓ backfilled sudo-password on ${fleet}-ssh in $ns"
  fi
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# OpenSSH-format private key; the operator parses it with ssh.ParsePrivateKey,
# which accepts it, and the .pub is already in authorized_keys form.
ssh-keygen -t ed25519 -f "$tmp/id_ed25519" -N '' -C "$fleet" >/dev/null

"${kube[@]}" -n "$ns" create secret generic "${fleet}-ssh" \
  --from-file=id_ed25519="$tmp/id_ed25519" \
  --from-file=id_ed25519.pub="$tmp/id_ed25519.pub" \
  --from-literal=sudo-password="$sudopw"
"${kube[@]}" -n "$ns" label secret "${fleet}-ssh" \
  tuist.dev/managed-by=capi-scaleway-applesilicon "tuist.dev/fleet=${fleet}" --overwrite >/dev/null

echo "✓ minted ${fleet}-ssh in $ns"
