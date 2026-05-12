#!/usr/bin/env bash
#MISE description="Pre-generate a CAPI fleet's SSH keypair and stage it as a K8s Secret on the workload cluster, so the controller adopts pre-ordered Mac minis on the first deploy instead of failing to SSH in. Prints the public key + operator install steps for the existing pool hosts."
#USAGE arg "<env>" help="Environment (staging | canary | production)"
#USAGE arg "<fleet_name>" help="Fleet name (matches the MachineDeployment / Secret prefix, e.g. tuist-tuist-runners-fleet)"
#USAGE arg "[scaleway_project_label]" help="Optional Scaleway project label for the SSH-key registration name (default: <fleet_name>)"

# Operator workflow for adopting a pre-ordered Mac mini pool:
#
#   1. Operator orders N Mac minis in the Scaleway console with
#      names matching the pool prefix (default `tuist-pool-`).
#   2. *This script* (run BEFORE the deploy):
#        - Generates an ed25519 keypair under
#          `tuist-capi-<fleet>` (matching what
#          `Manager.generateSSHKey` in the CAPI provider would
#          produce on first reconcile).
#        - Creates the per-fleet Secret `<fleet>-ssh` on the
#          workload cluster, with `id_ed25519` + `id_ed25519.pub`
#          keys. The CAPI controller's `EnsureFleetSSHKey` finds
#          this Secret on first reconcile and uses it instead of
#          generating a fresh one (the Scaleway-side registration
#          still happens lazily — the controller stamps the
#          `scaleway.tuist.dev/ssh-key-id` annotation after it
#          posts the pubkey to IAM).
#   3. Operator installs the printed public key on each
#      pre-ordered Mac mini ONCE, before the deploy. Two options
#      (both safe — they're each per-host one-time work):
#        a. Scaleway web console → VNC → open Terminal → paste
#           the printed install one-liner.
#        b. SSH with the Scaleway-issued bootstrap password
#           (visible in the order email or `scw apple-silicon
#           server password` if still in the bootstrap window;
#           Scaleway stops exposing it shortly after first boot).
#   4. CI runs the deploy; the CAPI controller adopts each
#      pre-ordered Mac mini, dials SSH with the now-pre-installed
#      key, and bootstraps tart-kubelet without forcing a
#      reinstall.
#
# Re-runs are safe. If the Secret already exists the script
# refuses to overwrite (no silent key rotation behind the
# operator's back); pass `--force` to regenerate after deleting
# all hosts that use the key.

set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <env> <fleet_name> [scaleway_project_label]" >&2
  echo "  env:                     staging | canary | production" >&2
  echo "  fleet_name:              e.g. tuist-tuist-runners-fleet" >&2
  echo "  scaleway_project_label:  optional, default <fleet_name>" >&2
  exit 64
fi

ENV="$1"
FLEET="$2"
SCW_LABEL="${3:-$FLEET}"
FORCE="${FORCE:-0}"

case "$ENV" in
  staging|canary|production) ;;
  *) echo "ERROR: env must be one of staging|canary|production" >&2; exit 64 ;;
esac

# Map env -> 1Password vault + workload kubeconfig item. Matches
# the convention used by infra/mise/tasks/k8s/bootstrap-workload.sh
# and the `op document get "kubeconfig: tuist-${env}"` line in
# .github/workflows/server-deployment.yml.
case "$ENV" in
  staging)    VAULT_NAME="tuist-k8s-staging"    ;  KUBECONFIG_ITEM="kubeconfig: tuist-staging" ;;
  canary)     VAULT_NAME="tuist-k8s-canary"     ;  KUBECONFIG_ITEM="kubeconfig: tuist-canary" ;;
  production) VAULT_NAME="tuist-k8s-production" ;  KUBECONFIG_ITEM="kubeconfig: tuist-production" ;;
esac

# Namespace where the chart's CAPI provider deployment runs. Matches
# the helm release's namespace, which the deploy workflow maps as
# `tuist-${env}` for staging/canary and bare `tuist` for production.
case "$ENV" in
  staging)    NAMESPACE="tuist-staging" ;;
  canary)     NAMESPACE="tuist-canary" ;;
  production) NAMESPACE="tuist" ;;
esac

SECRET_NAME="${FLEET}-ssh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
err() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; }

# ---------------------------------------------------------------------------
log "Step 1/4: fetch workload kubeconfig from 1Password ($VAULT_NAME)"

KUBECONFIG_FILE="$WORKDIR/kubeconfig"
op document get "$KUBECONFIG_ITEM" --vault "$VAULT_NAME" --output "$KUBECONFIG_FILE"
chmod 600 "$KUBECONFIG_FILE"

# Sanity-check that the kubeconfig works and the target namespace
# exists. If the operator runs this against the wrong env, the
# wrong-namespace check fails fast instead of writing a Secret
# into an unexpected cluster.
if ! KUBECONFIG="$KUBECONFIG_FILE" kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  err "Namespace $NAMESPACE not found on the $ENV workload cluster (kubeconfig from 1P item $KUBECONFIG_ITEM)."
  err "Has the chart been installed there yet?"
  exit 1
fi

# ---------------------------------------------------------------------------
log "Step 2/4: check for an existing $SECRET_NAME Secret"

if KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  if [ "$FORCE" != "1" ]; then
    err "Secret $NAMESPACE/$SECRET_NAME already exists on the $ENV cluster."
    err "Refusing to overwrite — silent key rotation would lock the CAPI controller"
    err "out of any Mac minis registered with the previous key."
    err ""
    err "If you really want to rotate:"
    err "  1. Delete all CAPI-managed hosts that adopted the old key:"
    err "       KUBECONFIG=<wl> kubectl -n $NAMESPACE delete scalewayapplesiliconmachines.infrastructure.cluster.x-k8s.io -l tuist.dev/fleet=$FLEET"
    err "  2. Re-run with FORCE=1: FORCE=1 $0 $ENV $FLEET"
    exit 1
  fi

  log "FORCE=1 set — deleting existing $SECRET_NAME"
  KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" delete secret "$SECRET_NAME"
fi

# ---------------------------------------------------------------------------
log "Step 3/4: generate ed25519 keypair and stage Secret $NAMESPACE/$SECRET_NAME"

# Mirror the controller's `generateSSHKey`: ed25519 algorithm,
# OpenSSH-format PEM, comment `tuist-capi-<fleet>`. The two
# representations of the public key (authorized_keys vs PEM)
# both live in the Secret so the controller — or this script —
# can pick whichever it needs.
PRIV_KEY="$WORKDIR/id_ed25519"
PUB_KEY="$WORKDIR/id_ed25519.pub"
ssh-keygen -q -t ed25519 -N "" -C "tuist-capi-$FLEET" -f "$PRIV_KEY"

# Create the Secret matching the layout the controller writes
# in `generateSSHKey`: data keys `id_ed25519` (private PEM) and
# `id_ed25519.pub` (authorized_keys form). No
# `scaleway.tuist.dev/ssh-key-id` annotation — the controller's
# re-registration path notices its absence on first reconcile
# and posts the pubkey to Scaleway IAM at that point.
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-file=id_ed25519="$PRIV_KEY" \
  --from-file=id_ed25519.pub="$PUB_KEY"

# Stamp the fleet label so the Secret survives helm-managed
# label conventions and is findable by ops via `-l tuist.dev/fleet=…`.
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" label secret "$SECRET_NAME" \
  "tuist.dev/fleet=$FLEET" \
  "app.kubernetes.io/component=capi-provider-scaleway-applesilicon" \
  --overwrite

# ---------------------------------------------------------------------------
log "Step 4/4: ready — operator install steps"

PUB_KEY_CONTENT=$(cat "$PUB_KEY")

cat <<EOF

The Secret is staged. Each pre-ordered Mac mini now needs three
things in place BEFORE the next deploy so the CAPI controller can
adopt it without needing the Scaleway-issued bootstrap password
(which Scaleway only surfaces for ~hours after server creation —
older pool hosts can no longer be bootstrapped via the API):

  1. The SSH pubkey below in ~m1/.ssh/authorized_keys (so the
     controller can dial in with the staged K8s Secret keypair).
  2. /etc/sudoers.d/m1-nopasswd granting m1 passwordless sudo
     (so the controller doesn't need the m1 password to run
     sudo during bootstrap).
  3. /etc/kcpassword + autoLoginUser preference configured so
     macOS auto-logs-in the m1 user at boot. Tart's
     Virtualization framework refuses to start guests without a
     live Aqua session, and the controller can't write a usable
     kcpassword without the password (kcpassword is the m1
     password XOR'd with Apple's well-known cipher), so this
     step lives operator-side too.

  ┌─ Public key to install on every pre-ordered Mac mini ─────────
  │
  │  $PUB_KEY_CONTENT
  │
  └────────────────────────────────────────────────────────────────

OPTION A — VNC (recommended for a handful of hosts):

  For each pre-ordered Mac mini in the $ENV Scaleway project:

    1. Open Scaleway console → Apple Silicon → click the server.
    2. Reveal the m1 password (Access section → "Show" next to
       Password) and copy it.
    3. Click "Open remote desktop" to start a VNC session.
    4. Once logged into macOS, open Terminal (Spotlight → Terminal).
    5. Paste this block (idempotent — safe to re-run; will prompt
       once for the m1 password you copied in step 2):

       read -rsp 'm1 password: ' SUDO_PW; echo
       mkdir -p ~/.ssh && chmod 700 ~/.ssh
       grep -qxF '$PUB_KEY_CONTENT' ~/.ssh/authorized_keys 2>/dev/null \\
         || echo '$PUB_KEY_CONTENT' >> ~/.ssh/authorized_keys
       chmod 600 ~/.ssh/authorized_keys
       if [ ! -f /etc/sudoers.d/m1-nopasswd ]; then
         printf '%s\n' "\$SUDO_PW" | sudo -S sh -c \\
           "echo 'm1 ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/m1-nopasswd && chmod 440 /etc/sudoers.d/m1-nopasswd"
       fi
       python3 -c "import sys; key=bytes([0x7d,0x89,0x52,0x23,0xd2,0xbc,0xdd,0xea,0xa3,0xb9,0x1f]); pw=sys.argv[1].encode(); pad=len(key)-(len(pw)%len(key)); pw+=b'\\x00'*pad; sys.stdout.buffer.write(bytes(b ^ key[i%len(key)] for i,b in enumerate(pw)))" "\$SUDO_PW" \\
         | sudo tee /etc/kcpassword > /dev/null
       sudo chmod 600 /etc/kcpassword
       sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser 'm1'
       sudo killall -HUP loginwindow 2>/dev/null || true
       unset SUDO_PW
       echo "✓ Mac mini prepared"

    6. (Optional sanity check) Verify the three artifacts are in
       place:

       test -f /etc/sudoers.d/m1-nopasswd && test -f /etc/kcpassword \\
         && grep -qxF '$PUB_KEY_CONTENT' ~/.ssh/authorized_keys \\
         && sudo -n true \\
         && echo "✓ ready for adoption" \\
         || echo "✗ one of {sudoers, kcpassword, authorized_keys, passwordless sudo} is missing — re-run step 5"

    7. Close the VNC session. The host is ready for the deploy.

OPTION B — SSH with the Scaleway bootstrap password (faster if
the order-time password is still surfaced — typically only the
first few hours after creation):

  Set the password in your shell once:

    read -rsp 'm1 password: ' SUDO_PW; echo
    export SSHPASS="\$SUDO_PW"

  Then per host:

    sshpass -e ssh -o StrictHostKeyChecking=accept-new m1@<server-ip> \\
      "SUDO_PW='\$SUDO_PW' PUB_KEY='$PUB_KEY_CONTENT' bash -s" <<'REMOTE'
    set -euo pipefail
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    grep -qxF "\$PUB_KEY" ~/.ssh/authorized_keys 2>/dev/null \\
      || echo "\$PUB_KEY" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    if [ ! -f /etc/sudoers.d/m1-nopasswd ]; then
      printf '%s\n' "\$SUDO_PW" | sudo -S sh -c \\
        "echo 'm1 ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/m1-nopasswd && chmod 440 /etc/sudoers.d/m1-nopasswd"
    fi
    python3 -c "import sys; key=bytes([0x7d,0x89,0x52,0x23,0xd2,0xbc,0xdd,0xea,0xa3,0xb9,0x1f]); pw=sys.argv[1].encode(); pad=len(key)-(len(pw)%len(key)); pw+=b'\x00'*pad; sys.stdout.buffer.write(bytes(b ^ key[i%len(key)] for i,b in enumerate(pw)))" "\$SUDO_PW" \\
      | sudo tee /etc/kcpassword > /dev/null
    sudo chmod 600 /etc/kcpassword
    sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser 'm1'
    sudo killall -HUP loginwindow 2>/dev/null || true
    REMOTE

WHEN THE DEPLOY RUNS:

  * The CAPI controller's EnsureFleetSSHKey finds
    $NAMESPACE/$SECRET_NAME on the workload cluster and uses
    THIS keypair (no fresh generation).
  * It posts the pubkey to Scaleway IAM under name "$SCW_LABEL"
    on the first reconcile (the annotation gets stamped at that
    point), so future fresh provisions (not adoption) also get
    the same key.
  * Adoption: rename a tuist-pool-* host → SSH dial with this
    private key → succeeds because YOU installed it above →
    enablePasswordlessSudo no-ops (file exists) →
    enableAutoLogin no-ops (controller has no password and bails
    safely rather than overwriting your kcpassword) → the rest
    of the bootstrap (Tart install, tart-kubelet binary,
    kubeconfig, launchd plist) all run via the passwordless
    sudo you seeded.

EOF
