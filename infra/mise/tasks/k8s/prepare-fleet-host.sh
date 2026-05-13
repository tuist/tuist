#!/usr/bin/env bash
#MISE description="Stage SSH key + passwordless sudo + auto-login on a pre-ordered Mac mini so the CAPI controller can adopt it without ever touching the Scaleway-issued sudo password."
#USAGE arg "<env>" help="Environment (staging | canary | production)"
#USAGE arg "<fleet_name>" help="Fleet name matching the Secret prefix (e.g. tuist-tuist-runners-fleet)"
#USAGE arg "<host_ip>" help="Mac mini external IP (from Scaleway console > server > Access)"

# Why this exists (and what it does):
#
# `prepare-fleet-ssh-key.sh` generates the per-fleet SSH keypair and
# stages it as a K8s Secret on the workload cluster. The CAPI
# controller's bootstrap then needs three on-host artifacts to take
# over from there:
#
#   1. The fleet pubkey in ~m1/.ssh/authorized_keys (so the
#      controller's SSH dial succeeds).
#   2. /etc/sudoers.d/m1-nopasswd (so the controller doesn't need to
#      know the m1 password to run sudo during bootstrap).
#   3. /etc/kcpassword + autoLoginUser preference (so macOS
#      auto-logs-in m1 and Tart's VZ framework finds the Aqua
#      session it requires).
#
# (1) is auto-installed by Scaleway IAM if the fleet pubkey is
# registered at the Scaleway project level BEFORE the Mac mini is
# provisioned. For pool hosts pre-ordered before the chart was
# deployed (which is the whole point of `adoptPoolPrefix`), the
# pubkey isn't on the host yet — this script installs it.
#
# (2) and (3) need the m1 password. Scaleway only surfaces that
# password for ~hours after server creation, so pool hosts that sat
# idle longer can't be bootstrapped via the controller's password
# code path. This script asks the operator for it once
# (interactively, never echoed) and stages everything in one round-
# trip. After the script finishes the controller's reconcile is
# fully unblocked.
#
# Two SSH transport modes:
#   * If the fleet pubkey is already on the host (e.g. Scaleway
#     IAM auto-injected it because the operator added the key at
#     the project level), we use it. No external dep.
#   * Otherwise we fall back to `sshpass` with the m1 password.
#     Requires `sshpass` on the operator's machine
#     (`brew install hudochenkov/sshpass/sshpass` on macOS).
#
# Idempotent — safe to re-run on a partially-prepped host. The
# existence checks on the remote mean a second invocation only
# fixes what's missing.

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
log "Step 2/4: extract fleet keypair from Secret $NAMESPACE/$SECRET_NAME"

if ! KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  err "Secret $NAMESPACE/$SECRET_NAME doesn't exist."
  err "Run \`mise run k8s:prepare-fleet-ssh-key $ENV $FLEET\` first to stage it."
  exit 1
fi

PRIV_KEY="$WORKDIR/id_ed25519"
PUB_KEY_FILE="$WORKDIR/id_ed25519.pub"
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" \
  get secret "$SECRET_NAME" \
  -o jsonpath='{.data.id_ed25519}' | base64 -d > "$PRIV_KEY"
chmod 600 "$PRIV_KEY"
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" \
  get secret "$SECRET_NAME" \
  -o jsonpath='{.data.id_ed25519\.pub}' | base64 -d > "$PUB_KEY_FILE"
PUB_KEY=$(cat "$PUB_KEY_FILE")

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
# on the operator's machine (vs the remote heredoc) sidesteps a
# nested-heredoc shell-quoting bug: when `python3 - "$SUDO_PW"
# <<'PY' ... PY` is the inner heredoc inside an outer `bash -s`
# heredoc, the remote bash's heredoc parser doesn't reliably pass
# the password through to python's sys.argv[1]; result is an
# empty-string kcpassword (just the cipher key XOR'd with nulls),
# macOS loginwindow auto-login fails, no Aqua session, Tart can't
# start VMs. Encoding here keeps the only password-touching code
# in a place we can validate without an SSH round trip.
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
log "Step 4/4: probe SSH transport, then run on-host prep"

SSH_OPTS=(
  -T
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=8
  -o IdentitiesOnly=yes
  -o IdentityAgent=none
)
# `-T` disables pseudo-TTY allocation. We feed the remote
# `bash -s` body via a heredoc on stdin, so a TTY would
# fight with the heredoc and surface as
# `Failed to get a pseudo terminal: Device not configured`
# (especially under sshpass, which doesn't have a controlling
# terminal of its own to forward).
#
# `IdentitiesOnly=yes` + `IdentityAgent=none` force ssh to use
# only the key we pass via `-i`, ignoring the operator's SSH
# agent (1Password, ssh-add cache) and ~/.ssh/id_* defaults.
# Without this, sshd hits MaxAuthTries (6) trying the agent and
# default keys before it ever gets to ours, and the server cuts
# off auth with `Permission denied (publickey)` even though our
# key is correct.

# If the fleet key is already on the host we can use it directly —
# common case once the operator has registered the key at the
# Scaleway project IAM level so newly-provisioned hosts have it
# pre-baked, on a re-run after a previous prep installed it, or
# after a previous controller adoption that already installed it
# before its bootstrap failed for other reasons (sudo / autologin).
# BatchMode=yes refuses password fallback, so this probe doesn't
# block on a prompt.
#
# Retried up to 5 times with a 5s delay because Mac mini sshd can
# take 30-60s to come back after a reboot — common case if the
# operator just rebooted the host to drain a PAM lockout. We keep
# stderr visible so a real failure surfaces clearly rather than
# silently falling through to the sshpass branch (which then dies
# with a confusing TTY error if sshpass is missing or broken).
probe_ssh_key() {
  local attempts=5
  local i=1
  while [ $i -le $attempts ]; do
    if ssh -i "$PRIV_KEY" "${SSH_OPTS[@]}" -o BatchMode=yes "m1@$HOST_IP" true; then
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

if probe_ssh_key; then
  printf '    transport: ssh key (fleet pubkey already on host)\n'
  SSH_CMD=(ssh -i "$PRIV_KEY" "${SSH_OPTS[@]}")
else
  printf '    transport: sshpass + bootstrap password (fleet pubkey will be installed by this run)\n'
  if ! command -v sshpass >/dev/null; then
    err "sshpass not installed. Either:"
    err "  * brew install hudochenkov/sshpass/sshpass"
    err "  * or install the fleet pubkey on the host first (Scaleway"
    err "    console > Apple Silicon > server > Open remote desktop;"
    err "    paste the pubkey from $PUB_KEY_FILE into ~/.ssh/authorized_keys),"
    err "    then re-run this script (it'll take the SSH-key transport path)."
    exit 1
  fi
  SSH_CMD=(env "SSHPASS=$SUDO_PW" sshpass -e ssh "${SSH_OPTS[@]}")
fi

# Heredoc with `'REMOTE'` (no expansion) — variables stay
# inside the remote shell so we don't have to escape every `$`.
# Operator-side `$PUB_KEY` / `$SUDO_PW` get passed through the
# `bash -s` env declaration on the SSH command line.
"${SSH_CMD[@]}" "m1@$HOST_IP" "PUB_KEY='$PUB_KEY' SUDO_PW='$SUDO_PW' KCPW_B64='$KCPW_B64' bash -s" <<'REMOTE'
set -euo pipefail

# 1. Append the fleet pubkey to authorized_keys (idempotent).
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if grep -qxF "$PUB_KEY" ~/.ssh/authorized_keys 2>/dev/null; then
  printf '  ✓ ssh pubkey: already present\n'
else
  printf '%s\n' "$PUB_KEY" >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  printf '  ✓ ssh pubkey: installed\n'
fi

# 2. Passwordless sudoers (idempotent).
if [ -f /etc/sudoers.d/m1-nopasswd ]; then
  printf '  ✓ sudoers: already present\n'
else
  printf '%s\n' "$SUDO_PW" | sudo -S sh -c \
    "echo 'm1 ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/m1-nopasswd && chmod 440 /etc/sudoers.d/m1-nopasswd"
  printf '  ✓ sudoers: installed\n'
fi

# 3. /etc/kcpassword (XOR-encoded m1 password) + autoLoginUser
#    preference. The encoded blob is computed operator-side and
#    arrives as $KCPW_B64; re-applied every run because there's
#    no cheap idempotency check we trust on the encoded contents,
#    and sudo is now passwordless so the write is free.
printf '%s' "$KCPW_B64" | base64 -d | sudo tee /etc/kcpassword > /dev/null
sudo chmod 600 /etc/kcpassword
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser 'm1'
sudo killall -HUP loginwindow 2>/dev/null || true
printf '  ✓ kcpassword + autoLoginUser: configured\n'

# 4. Verify. macOS auto-login needs a full reboot on headless
#    hosts before loginwindow honors the autoLoginUser preference
#    and brings up an Aqua session — without that session Tart's
#    VZ framework refuses to start guests. Surface that next
#    step to the operator rather than calling it a success and
#    moving on.
if sudo -n true && test -f /etc/kcpassword; then
  printf '\n  ✓ host prepped — reboot the Mac mini in the Scaleway console for auto-login to take effect\n'
else
  printf '\n  ✗ verification failed — check the previous steps\n' >&2
  exit 1
fi
REMOTE

unset SUDO_PW

cat <<EOF

The host at $HOST_IP is now prepared. On the next CAPI
reconcile (typically <60s) the controller will:

  * SSH-dial in with $NAMESPACE/$SECRET_NAME's private key
    (works because step 1 above installed the pubkey).
  * Skip enablePasswordlessSudo (file exists, step 2).
  * Skip enableAutoLogin (controller's UserPassword is empty;
    leaves your kcpassword from step 3 alone).
  * Proceed with disable-idle-sleep / set-hostname /
    install-tart / install-vm-egress-firewall / write-kubeconfig
    / install-tart-kubelet / launchd-plist — all via the now-
    passwordless sudo path.

If the host is already past the "Adopting" SASM phase and stuck
in "Bootstrapping" because a previous reconcile tried to seed
sudo with the wrong password and PAM-locked the m1 account,
you'll need to reset that lockout once via VNC before the next
reconcile can take effect:

  sudo dscl . -delete /Users/m1 AuthenticationAuthority ';tally;'
  sudo pwpolicy -u m1 -clearaccountpolicies

EOF
