#!/usr/bin/env bash
# Render a node's Ubuntu autoinstall config into a directory.
# Sourced by the rack:* tasks: render_autoinstall <node> <outdir> <ssh-pubkey>

render_autoinstall() {
  local node="$1" outdir="$2" ssh_key="$3"
  local root inventory entry install_user packages key_material layout

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

  # macOS ships LibreSSL as openssl, whose passwd has no -6: without this the
  # failure is a usage dump from a tool the caller never named.
  if ! openssl passwd -6 "" >/dev/null 2>&1; then
    echo "error: need an openssl with SHA-512 crypt support (brew install openssl)" >&2
    return 1
  fi

  ssh_key="${ssh_key/#\~/$HOME}"
  if [ ! -f "$ssh_key" ]; then
    echo "error: no such public key: $ssh_key" >&2
    return 1
  fi
  key_material="$(tr -d '\n' < "$ssh_key")"
  # The public and private key differ by one suffix, and this value is baked
  # into an image, written to removable media and served over plain HTTP.
  case "$key_material" in
    ssh-*|ecdsa-*|sk-ssh-*|sk-ecdsa-*) ;;
    *)
      echo "error: $ssh_key does not look like an SSH public key" >&2
      return 1
      ;;
  esac
  packages="$(jq -r '.packages | map("    - " + .) | join("\n")' <<<"$entry")"

  # The account is a console login of last resort; over the network only the key
  # is accepted. Its password lives in 1Password rather than being generated and
  # thrown away, or the machine has no way in when the network is the problem.
  local vault item op_args
  vault="$(jq -r '.vault' "$inventory")"
  item="$(jq -r '.credential_item' <<<"$entry")"
  op_args=(item get "$item" --vault "$vault" --format=json)
  [ -n "${OP_ACCOUNT:-}" ] && op_args+=(--account "$OP_ACCOUNT")

  if ! op "${op_args[@]}" >/dev/null 2>&1; then
    local create_args
    # shellcheck disable=SC2054  # commas belong to op's own flag values
    create_args=(item create --category=login "--title=$item" --vault "$vault"
                 --generate-password=letters,digits,24 --tags=ber1,rack,node
                 "username=$install_user")
    [ -n "${OP_ACCOUNT:-}" ] && create_args+=(--account "$OP_ACCOUNT")
    op "${create_args[@]}" >/dev/null
  fi

  local password password_hash
  password="$(op "${op_args[@]}" | jq -r '.fields[] | select(.id=="password") | .value')"
  if [ -z "$password" ]; then
    echo "error: could not read the console password for $node from 1Password" >&2
    return 1
  fi
  password_hash="$(openssl passwd -6 "$password")"

  local role built
  role="$(jq -r '.role' <<<"$entry")"
  built="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

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
    # Ubuntu leaves the first user needing a password for sudo, and the fleet is
    # driven over SSH by automation that has a key and no password.
    - |
      printf '%s ALL=(ALL) NOPASSWD:ALL\n' $install_user > /target/etc/sudoers.d/90-$install_user
    - chmod 440 /target/etc/sudoers.d/90-$install_user
    - |
      printf 'node=%s\nrole=%s\nbuilt=%s\n' '$node' '$role' '$built' > /target/etc/tuist-rack-node
    - chmod 444 /target/etc/tuist-rack-node
EOF
}
