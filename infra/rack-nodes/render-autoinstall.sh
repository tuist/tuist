#!/usr/bin/env bash
# Renders a rack Linux host's Ubuntu autoinstall seed into a directory.
# Sourced: render_autoinstall <outdir> <host-json> <password-hash> <authorized-keys-file> <tailnet-key-file> <tailnet-key-id>
#
# The installed machine joins the tailnet by itself on first boot, with the
# single-use key in <tailnet-key-file>, and deletes the key once it has. The
# cluster does the rest: the RackLinuxHost controller finds the device and the
# RackLinuxMachine controller joins the host over the tailnet.

render_autoinstall() {
  local outdir="$1" host_json="$2" password_hash="$3" keys_file="$4" tailnet_key_file="$5" tailnet_key_id="$6"
  local node role user tags built key authorized_keys

  node="$(jq -r '.name' <<<"$host_json")"
  role="$(jq -r '.role' <<<"$host_json")"
  user="$(jq -r '.sshUser' <<<"$host_json")"
  tags="$(jq -r '.tailnetTags | join(",")' <<<"$host_json")"

  case "$role" in
    edge|services) ;;
    storage)
      echo "error: the storage layout is not implemented. A storage node needs /boot, a capped /," >&2
      echo "       and a separate XFS /data with project quotas, fixed at install time; work it out" >&2
      echo "       against controllers/linux/linux_cloudinit.go before installing $node." >&2
      return 1
      ;;
    *)
      echo "error: $node has no known role ('$role')" >&2
      return 1
      ;;
  esac
  if [ -z "$tags" ]; then
    echo "error: $node has no tailnetTags" >&2
    return 1
  fi

  key="$(tr -d '\n' <"$tailnet_key_file")"
  case "$key" in
    tskey-auth-*) ;;
    *)
      echo "error: $tailnet_key_file does not hold a tailnet auth key" >&2
      return 1
      ;;
  esac

  authorized_keys=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      ssh-*|ecdsa-*|sk-ssh-*|sk-ecdsa-*) ;;
      *)
        echo "error: an authorized key does not look like an SSH public key" >&2
        return 1
        ;;
    esac
    authorized_keys+="      - \"$line\""$'\n'
  done <"$keys_file"
  if [ -z "$authorized_keys" ]; then
    echo "error: no authorized keys for $node" >&2
    return 1
  fi

  built="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$outdir"
  : >"$outdir/meta-data"
  : >"$outdir/vendor-data"

  cat >"$outdir/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:
    hostname: $node
    username: $user
    password: "$password_hash"
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
$authorized_keys  storage:
    layout:
      name: direct
  packages:
    - curl
    - ca-certificates
    - jq
    - ethtool
  updates: security
  shutdown: reboot
  early-commands:
    - |
      mkdir -p /run/tuist-prev
      for part in \$(lsblk -rpno NAME,FSTYPE | awk '\$2 == "ext4" {print \$1}'); do
        mount -o ro "\$part" /run/tuist-prev 2>/dev/null || continue
        if grep -qx 'tailnet_key=$tailnet_key_id' /run/tuist-prev/etc/tuist-rack-node 2>/dev/null; then
          for fs in dev proc sys; do mount --rbind "/\$fs" "/run/tuist-prev/\$fs"; done
          entry=\$(chroot /run/tuist-prev efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} [Uu]buntu.*/\1/p' | head -n 1)
          [ -n "\$entry" ] && chroot /run/tuist-prev efibootmgr -q -n "\$entry"
          echo "tuist: this stick already installed $node; booting the installed system" >/dev/console
          umount -R /run/tuist-prev
          reboot -f
        fi
        umount /run/tuist-prev
      done
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
    - |
      printf '%s ALL=(ALL) NOPASSWD:ALL\n' '$user' > /target/etc/sudoers.d/90-$user
      chmod 440 /target/etc/sudoers.d/90-$user
    - |
      mkdir -p /target/etc/tuist
      printf 'TAILNET_TAGS=%s\n' '$tags' > /target/etc/tuist/tailnet.env
      printf '%s\n' '$key' > /target/etc/tuist/tailnet-auth-key
      chmod 600 /target/etc/tuist/tailnet-auth-key
    - |
      cat > /target/usr/local/sbin/tuist-tailnet-join <<'TUIST_EOF'
      #!/usr/bin/env bash
      set -euo pipefail
      . /etc/tuist/tailnet.env
      key=/etc/tuist/tailnet-auth-key
      if ! command -v tailscale >/dev/null 2>&1; then
        . /etc/os-release
        curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/\$VERSION_CODENAME.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
        curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/\$VERSION_CODENAME.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
        apt-get -o DPkg::Lock::Timeout=600 update -qq
        DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y -qq tailscale
      fi
      systemctl enable --now tailscaled
      if [ "\$(tailscale status --json 2>/dev/null | jq -r '.BackendState')" != Running ]; then
        if [ ! -s "\$key" ]; then
          echo "tuist-tailnet-join: no join key; join by hand: tailscale up --hostname=\$(hostname) --advertise-tags=\$TAILNET_TAGS" >&2
          exit 1
        fi
        tailscale up --auth-key="file:\$key" --hostname="\$(hostname)" --advertise-tags="\$TAILNET_TAGS" --ssh=false --timeout=120s
      fi
      rm -f "\$key"
      systemctl disable tuist-tailnet-join.service
      TUIST_EOF
      chmod 755 /target/usr/local/sbin/tuist-tailnet-join
    - |
      cat > /target/etc/systemd/system/tuist-tailnet-join.service <<'TUIST_EOF'
      [Unit]
      Description=Join the tailnet with the install stick's key
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0
      [Service]
      Type=oneshot
      ExecStart=/usr/local/sbin/tuist-tailnet-join
      Restart=on-failure
      RestartSec=60
      [Install]
      WantedBy=multi-user.target
      TUIST_EOF
    - curtin in-target --target=/target -- systemctl enable tuist-tailnet-join.service
    - |
      printf 'node=%s\nrole=%s\nbuilt=%s\ntailnet_key=%s\n' '$node' '$role' '$built' '$tailnet_key_id' > /target/etc/tuist-rack-node
      chmod 444 /target/etc/tuist-rack-node
EOF
}
