#!/usr/bin/env bash
# Render a node's Ubuntu autoinstall config into a directory.
# Sourced by the rack:* tasks: render_autoinstall <node> <outdir> <ssh-pubkey>

render_autoinstall() {
  local node="$1" outdir="$2" ssh_key="$3"
  local root inventory entry install_user packages key_material password_hash layout

  root="$(git rev-parse --show-toplevel)"
  inventory="$root/infra/rack-nodes/nodes.json"
  entry="$(jq -r --arg n "$node" '.nodes[$n]' "$inventory")"
  install_user="$(jq -r '.install_user' "$inventory")"
  layout="$(jq -r '.layout' <<<"$entry")"

  if [ "$layout" = "storage" ]; then
    echo "error: the storage layout is not implemented yet." >&2
    echo "       Cluster nodes need /boot, a capped /, and a separate XFS /data with" >&2
    echo "       project quotas; the self-join refuses a machine that cannot enforce" >&2
    echo "       them, and partitioning cannot be changed afterwards. Work it out" >&2
    echo "       against controllers/linux/linux_cloudinit.go before installing $node." >&2
    return 1
  fi

  ssh_key="${ssh_key/#\~/$HOME}"
  if [ ! -f "$ssh_key" ]; then
    echo "error: no such public key: $ssh_key" >&2
    return 1
  fi
  key_material="$(tr -d '\n' < "$ssh_key")"
  packages="$(jq -r '.packages | map("    - " + .) | join("\n")' <<<"$entry")"

  # The account exists so the installer is happy and as a console login of last
  # resort; over the network only the key is accepted.
  password_hash="$(openssl passwd -6 "$(openssl rand -base64 24)")"

  mkdir -p "$outdir"
  : > "$outdir/meta-data"
  : > "$outdir/vendor-data"

  cat > "$outdir/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:
    hostname: $node
    username: $install_user
    password: "$password_hash"
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - "$key_material"
  storage:
    layout:
      name: direct
  packages:
$packages
  updates: security
  shutdown: reboot
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
EOF
}
