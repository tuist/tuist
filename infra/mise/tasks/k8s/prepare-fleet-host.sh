#!/usr/bin/env bash
#MISE description="Install passwordless sudoers + auto-login on a pre-ordered Mac mini using the fleet SSH key so the CAPI controller's bootstrap can take over."
#USAGE arg "<env>" help="Environment (staging | canary | production)"
#USAGE arg "<fleet_name>" help="Fleet name matching the Secret prefix (e.g. tuist-tuist-runners-fleet)"
#USAGE arg "<host_ip>" help="Mac mini external IP (from Scaleway console > server > Access)"

# Why this exists (and what it does):
#
# `prepare-fleet-ssh-key.sh` generates the per-fleet SSH keypair and
# stages it as a K8s Secret on the workload cluster. Scaleway Apple
# Silicon hosts auto-inject all project-level SSH keys into
# `~m1/.ssh/scw_authorized_keys` at first boot, and the host's
# `sshd_config` is configured to read both `~/.ssh/authorized_keys`
# and `~/.ssh/scw_authorized_keys`. So once the operator's CAPI
# controller has called `EnsureFleetSSHKey` (which registers the
# fleet pubkey at the Scaleway project level), every newly-ordered
# pool host accepts the fleet private key out of the box — no
# operator action needed for SSH transport.
#
# What's NOT auto-set is the rest of CAPI's bootstrap prerequisites:
#
#   1. `/etc/sudoers.d/m1-nopasswd` — passwordless sudo. CAPI's
#      bootstrap module installs this with `sudo -S` using the
#      operator-stored m1 password from the bootstrap Secret. If
#      that Secret's password is wrong / stale / empty (host got
#      reinstalled, password rotated, controller crashed mid-store),
#      every subsequent sudo call in the bootstrap fails and the
#      reconciler loops indefinitely with `BootstrapFailed`.
#   2. `/etc/kcpassword` + `autoLoginUser` — needed for macOS to
#      auto-log-in m1 on boot, which Tart's Virtualization.framework
#      requires (it needs a live Aqua session to launch VMs).
#
# This script is the manual escape hatch: SSH in with the fleet
# private key, prompt the operator for the m1 password once, install
# the sudoers entry + kcpassword + autoLoginUser. After it runs the
# host is in the exact state CAPI's bootstrap would leave it after
# steps 2-3, so the bootstrap can resume from step 4 (Tart install)
# without ever needing a correct password in its Secret.
#
# Idempotent — safe to re-run on a partially-prepped host.
#
# # Failure mode: SSH key auth fails
#
# If the fleet pubkey isn't on the host (rare — Scaleway didn't
# inject for some reason, or the project key was rotated after the
# host was provisioned), the SSH probe below errors out with
# `Permission denied (publickey)`. Recover by either:
#
#   1. VNC into the host (Scaleway console > server > Open remote
#      desktop), open Terminal, paste the fleet pubkey into
#      `~/.ssh/scw_authorized_keys`. The pubkey is:
#
#        kubectl -n <ns> get secret <fleet>-ssh \
#          -o jsonpath='{.data.id_ed25519\.pub}' | base64 -d
#
#      Then re-run this script.
#
#   2. Reinstall the host (`scw apple-silicon server reinstall <id>
#      zone=<zone> os-id=<id>`). Scaleway re-injects current
#      project SSH keys on a fresh image at first boot. Then
#      re-run this script.

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Usage: $0 <env> <fleet_name> <host_ip>" >&2
  echo "  env:        staging | canary | production" >&2
  echo "  fleet_name: e.g. tuist-tuist-runners-fleet" >&2
  echo "  host_ip:    Mac mini external IP (Scaleway console)" >&2
  exit 64
fi

ENV="$1"
FLEET="$2"
HOST_IP="$3"

case "$ENV" in
  staging|canary|production) ;;
  *) echo "ERROR: env must be one of staging|canary|production" >&2; exit 64 ;;
esac

# Same mapping as prepare-fleet-ssh-key.sh.
case "$ENV" in
  staging)    VAULT_NAME="tuist-k8s-staging"    ;  KUBECONFIG_ITEM="kubeconfig: tuist-staging"    ;  NAMESPACE="tuist-staging" ;;
  canary)     VAULT_NAME="tuist-k8s-canary"     ;  KUBECONFIG_ITEM="kubeconfig: tuist-canary"     ;  NAMESPACE="tuist-canary" ;;
  production) VAULT_NAME="tuist-k8s-production" ;  KUBECONFIG_ITEM="kubeconfig: tuist-production" ;  NAMESPACE="tuist" ;;
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

# ---------------------------------------------------------------------------
log "Step 2/4: extract fleet private key from Secret $NAMESPACE/$SECRET_NAME"

if ! KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  err "Secret $NAMESPACE/$SECRET_NAME doesn't exist."
  err "Run \`mise run k8s:prepare-fleet-ssh-key $ENV $FLEET\` first to stage it."
  exit 1
fi

PRIV_KEY="$WORKDIR/id_ed25519"
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" \
  get secret "$SECRET_NAME" \
  -o jsonpath='{.data.id_ed25519}' | base64 -d > "$PRIV_KEY"
chmod 600 "$PRIV_KEY"

# ---------------------------------------------------------------------------
log "Step 3/4: collect m1 password (Scaleway console > server > Access > Show)"

# `read -rs` avoids the password ever hitting tty echo or shell
# history. `printf '\n'` keeps the next log line on a fresh row.
read -rsp 'm1 password: ' SUDO_PW
printf '\n'

if [ -z "$SUDO_PW" ]; then
  err "empty password"
  exit 1
fi

# Encode /etc/kcpassword locally and ship as base64. Doing this
# operator-side (vs in the remote heredoc) sidesteps a
# nested-heredoc shell-quoting bug where the password wouldn't
# reliably reach python's sys.argv on the remote bash.
KCPW_B64=$(python3 -c "
import sys, base64
key = bytes([0x7d, 0x89, 0x52, 0x23, 0xd2, 0xbc, 0xdd, 0xea, 0xa3, 0xb9, 0x1f])
pw = sys.stdin.buffer.read().rstrip(b'\\n')
pad = len(key) - (len(pw) % len(key))
pw += b'\\x00' * pad
enc = bytes(b ^ key[i % len(key)] for i, b in enumerate(pw))
sys.stdout.write(base64.b64encode(enc).decode())
" <<<"$SUDO_PW")
if [ -z "$KCPW_B64" ]; then
  err "failed to encode kcpassword locally"
  exit 1
fi

# ---------------------------------------------------------------------------
log "Step 4/4: SSH in with fleet key and run on-host prep"

# Common SSH options used for both the connectivity probe and the
# actual prep run.
#
# `-T` disables pseudo-terminal allocation. We feed the remote
# `bash -s` body via a heredoc on stdin, so a TTY would fight with
# the heredoc.
#
# `IdentitiesOnly=yes` + `IdentityAgent=none` force ssh to use only
# the key we pass via `-i`, ignoring the operator's SSH agent
# (1Password, ssh-add cache) and `~/.ssh/id_*` defaults. Without
# this, sshd may hit MaxAuthTries trying agent keys before the
# fleet key and reject before our key gets a chance.
#
# `UserKnownHostsFile=/dev/null` keeps Scaleway-IP reuse from
# wedging this script on a stale host-key entry from a previous
# server at the same IP. `StrictHostKeyChecking=accept-new` accepts
# the host's current key on first contact.
SSH_OPTS=(
  -T
  -i "$PRIV_KEY"
  -o IdentitiesOnly=yes
  -o IdentityAgent=none
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=10
)

# Probe SSH key auth before sending the password to the remote.
# Retried up to 5 times because sshd on a freshly-rebooted Mac mini
# can take 30-60s to come back up; we don't want to false-error
# during the operator's post-reinstall recovery flow.
probe_ssh_key() {
  local attempts=5
  local i=1
  while [ $i -le $attempts ]; do
    if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "m1@$HOST_IP" true; then
      return 0
    fi
    if [ $i -lt $attempts ]; then
      printf '    ssh-key probe attempt %d/%d failed; retrying in 5s (host may still be booting)\n' "$i" "$attempts" >&2
      sleep 5
    fi
    i=$((i + 1))
  done
  return 1
}

if ! probe_ssh_key; then
  err "SSH key auth failed at m1@$HOST_IP after 5 attempts."
  err ""
  err "Scaleway auto-injects project-level SSH keys at first boot, so"
  err "newly-ordered pool hosts normally have the fleet pubkey already."
  err "If this fails the pubkey isn't on this host — either the project"
  err "key was rotated after the host was provisioned, or Scaleway's"
  err "auto-inject didn't run for some reason."
  err ""
  err "Recovery (pick one):"
  err ""
  err "  1. VNC into the host and append the fleet pubkey to"
  err "     ~/.ssh/scw_authorized_keys, then re-run this script."
  err "     Pubkey content:"
  err ""
  err "       kubectl -n $NAMESPACE get secret $SECRET_NAME \\"
  err "         -o jsonpath='{.data.id_ed25519\\.pub}' | base64 -d"
  err ""
  err "  2. Reinstall the host so Scaleway re-injects current project"
  err "     keys at first boot, then re-run this script:"
  err ""
  err "       scw apple-silicon server reinstall <server-id> zone=<zone> \\"
  err "         os-id=<image-id>"
  exit 1
fi

printf '    transport: fleet SSH key works (Scaleway auto-injected at first boot)\n'

# Heredoc with `'REMOTE'` (no expansion) — variables stay inside
# the remote shell so we don't have to escape every `$`. Operator-
# side `$SUDO_PW` / `$KCPW_B64` get passed through the `bash -s`
# env declaration on the SSH command line.
ssh "${SSH_OPTS[@]}" "m1@$HOST_IP" "SUDO_PW='$SUDO_PW' KCPW_B64='$KCPW_B64' bash -s" <<'REMOTE'
set -euo pipefail

# 1. Passwordless sudoers (idempotent). The first sudo here needs
#    the m1 password via `sudo -S`; every subsequent sudo on this
#    host is passwordless because the file now exists.
if [ -f /etc/sudoers.d/m1-nopasswd ]; then
  printf '  ✓ sudoers: already present\n'
else
  printf '%s' "$SUDO_PW" | sudo -S sh -c \
    "echo 'm1 ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/m1-nopasswd && chmod 440 /etc/sudoers.d/m1-nopasswd" 2>/dev/null
  printf '  ✓ sudoers: installed\n'
fi

# Verify passwordless sudo is now active before we proceed.
if ! sudo -n true 2>/dev/null; then
  printf '  ✗ passwordless sudo not active — wrong m1 password?\n' >&2
  exit 1
fi

# 2. /etc/kcpassword (XOR-encoded m1 password) + autoLoginUser
#    preference. Re-applied every run because there's no cheap
#    idempotency check we trust on the encoded contents, and sudo
#    is now passwordless so the writes are free.
printf '%s' "$KCPW_B64" | base64 -d | sudo tee /etc/kcpassword > /dev/null
sudo chmod 600 /etc/kcpassword
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser 'm1'
sudo killall -HUP loginwindow 2>/dev/null || true
printf '  ✓ kcpassword + autoLoginUser: configured\n'

printf '\n  ✓ host prepped — reboot in the Scaleway console for auto-login to take effect\n'
REMOTE

unset SUDO_PW

cat <<EOF

The host at $HOST_IP is now prepared. On the next CAPI
reconcile (typically <60s) the controller will:

  * SSH-dial in with $NAMESPACE/$SECRET_NAME's private key.
  * Skip enablePasswordlessSudo (file exists from step 1 above).
  * Skip enableAutoLogin (controller's UserPassword either matches
    or isn't used; your kcpassword from step 2 stays in place).
  * Proceed with disable-idle-sleep / set-hostname / install-tart /
    install-vm-egress-firewall / write-kubeconfig /
    install-tart-kubelet / launchd-plist — all via the now-
    passwordless sudo path.

EOF
