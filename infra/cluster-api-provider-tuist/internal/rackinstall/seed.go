// Package rackinstall renders what installs a rack Linux host: the Ubuntu
// autoinstall seed, and the iPXE script that netboots the installer with it.
// The operator publishes both for PXE, and rack:write-install-usb bakes the
// same seed into an install stick.
package rackinstall

import (
	"fmt"
	"regexp"
	"strings"
	"time"
)

// Seed is everything one install is rendered from.
type Seed struct {
	Host string
	// Role is the host's role; storage is refused until its disk layout
	// exists.
	Role string
	User string
	// ConsolePassword is the console account's password. The installed
	// system hashes it: cloud-init sets it on the first boot.
	ConsolePassword string
	AuthorizedKeys  []string
	TailnetTags     []string
	// TailnetKey is the single-use join key, and TailnetKeyID its ID, which
	// the install records so a second boot of the same installer hands over
	// to the system it installed instead of wiping it.
	TailnetKey   string
	TailnetKeyID string
	Built        time.Time
	// HostKey, when set, is the SSH host key the install gives the host. A
	// seed baked into a per-host stick has none, and the host generates its
	// own.
	HostKey HostKey
}

// ModprobePath holds ModprobeConf, which keeps the MS-01's Bluetooth driver
// out: on a warm boot of the 6.8 kernel it dereferences NULL in hci_power_on,
// and a node's panic_on_oops turns that into a reboot loop. Rack nodes use no
// Bluetooth. The install writes it, and the operator's converge keeps it.
const (
	ModprobePath = "/etc/modprobe.d/tuist-rack.conf"
	ModprobeConf = "blacklist btusb\n"
)

var (
	hostPattern         = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`)
	keyIDPattern        = regexp.MustCompile(`^[A-Za-z0-9]+$`)
	consolePassword     = regexp.MustCompile(`^[A-Za-z0-9]{16,128}$`)
	tailnetKeyPattern   = regexp.MustCompile(`^tskey-auth-[A-Za-z0-9-]+$`)
	tagPattern          = regexp.MustCompile(`^tag:[a-z0-9-]+$`)
	authorizedKeyPrefix = regexp.MustCompile(`^(ssh-|ecdsa-|sk-ssh-|sk-ecdsa-)`)
)

func (s Seed) validate() error {
	switch s.Role {
	case "edge", "services":
	case "storage":
		return fmt.Errorf("the storage layout is not implemented: a storage node needs /boot, a capped / and a separate XFS /data with project quotas, fixed at install time")
	default:
		return fmt.Errorf("%s has no known role (%q)", s.Host, s.Role)
	}
	if !hostPattern.MatchString(s.Host) || !hostPattern.MatchString(s.User) {
		return fmt.Errorf("host %q or user %q is not a valid name", s.Host, s.User)
	}
	if len(s.TailnetTags) == 0 {
		return fmt.Errorf("%s has no tailnet tags", s.Host)
	}
	for _, tag := range s.TailnetTags {
		if !tagPattern.MatchString(tag) {
			return fmt.Errorf("%q is not a tailnet tag", tag)
		}
	}
	if !tailnetKeyPattern.MatchString(s.TailnetKey) {
		return fmt.Errorf("the tailnet key is not an auth key")
	}
	if !keyIDPattern.MatchString(s.TailnetKeyID) {
		return fmt.Errorf("%q is not a tailnet key ID", s.TailnetKeyID)
	}
	if !consolePassword.MatchString(s.ConsolePassword) {
		return fmt.Errorf("the console password is not 16 to 128 letters and digits")
	}
	if s.HostKey != (HostKey{}) {
		if err := s.HostKey.validate(); err != nil {
			return err
		}
	}
	if len(s.AuthorizedKeys) == 0 {
		return fmt.Errorf("no authorized keys for %s", s.Host)
	}
	for _, key := range s.AuthorizedKeys {
		if !authorizedKeyPrefix.MatchString(key) || strings.ContainsAny(key, "\"\n") {
			return fmt.Errorf("an authorized key does not look like an SSH public key")
		}
	}
	return nil
}

// UserData renders the autoinstall seed's user-data.
//
// It installs Ubuntu with the direct layout and DHCP on the SFP+ uplinks only
// (the MS-01's X710, driver i40e), so the 2.5G ports stay unmanaged for the
// node's pods. The installer creates the console account with a locked
// password, and cloud-init sets the password on the first boot, so the
// installed system hashes it. A first-boot unit joins the tailnet with the
// single-use key and deletes it. Early-commands look for an install carrying this key's ID and,
// finding one, boot it through BootNext rather than installing again: the
// MS-01s boot USB first, and a PXE boot can precede the disk too.
func UserData(s Seed) (string, error) {
	if err := s.validate(); err != nil {
		return "", err
	}
	var keys strings.Builder
	for _, key := range s.AuthorizedKeys {
		fmt.Fprintf(&keys, "      - \"%s\"\n", key)
	}
	tags := strings.Join(s.TailnetTags, ",")
	hostKey := ""
	if s.HostKey != (HostKey{}) {
		hostKey = "    - |\n" + indent(hostKeyCommand(s.HostKey), "      ")
	}
	built := s.Built.UTC().Format("2006-01-02T15:04:05Z")

	return fmt.Sprintf(`#cloud-config
# tuist-install-id: %[7]s
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:
    hostname: %[1]s
    username: %[2]s
    password: "!"
  user-data:
    chpasswd:
      expire: false
      users:
        - name: %[2]s
          password: "%[3]s"
          type: text
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
%[4]s  storage:
    layout:
      name: direct
  network:
    version: 2
    ethernets:
      uplinks:
        match:
          driver: i40e
        dhcp4: true
  packages:
    - curl
    - ca-certificates
    - jq
    - ethtool
  updates: security
  shutdown: reboot
  early-commands:
    - |
%[10]s  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
    - |
      printf '%%s ALL=(ALL) NOPASSWD:ALL\n' '%[2]s' > /target/etc/sudoers.d/90-%[2]s
      chmod 440 /target/etc/sudoers.d/90-%[2]s
    - |
      mkdir -p /target/etc/tuist
      printf 'TAILNET_TAGS=%%s\n' '%[5]s' > /target/etc/tuist/tailnet.env
      printf '%%s\n' '%[6]s' > /target/etc/tuist/tailnet-auth-key
      chmod 600 /target/etc/tuist/tailnet-auth-key
    - |
      cat > /target/usr/local/sbin/tuist-tailnet-join <<'TUIST_EOF'
      #!/usr/bin/env bash
      set -euo pipefail
      . /etc/tuist/tailnet.env
      key=/etc/tuist/tailnet-auth-key
      if ! command -v tailscale >/dev/null 2>&1; then
        . /etc/os-release
        curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
        curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
        apt-get -o DPkg::Lock::Timeout=600 update -qq
        DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y -qq tailscale
      fi
      systemctl enable --now tailscaled
      if [ "$(tailscale status --json 2>/dev/null | jq -r '.BackendState')" != Running ]; then
        if [ ! -s "$key" ]; then
          echo "tuist-tailnet-join: no join key; join by hand: tailscale up --hostname=$(hostname) --advertise-tags=$TAILNET_TAGS" >&2
          exit 1
        fi
        tailscale up --auth-key="file:$key" --hostname="$(hostname)" --advertise-tags="$TAILNET_TAGS" --ssh=false --timeout=120s
      fi
      rm -f "$key"
      systemctl disable tuist-tailnet-join.service
      TUIST_EOF
      chmod 755 /target/usr/local/sbin/tuist-tailnet-join
    - |
      cat > /target/etc/systemd/system/tuist-tailnet-join.service <<'TUIST_EOF'
      [Unit]
      Description=Join the tailnet with the install's key
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
      printf 'node=%%s\nrole=%%s\nbuilt=%%s\ntailnet_key=%%s\n' '%[1]s' '%[8]s' '%[9]s' '%[7]s' > /target/etc/tuist-rack-node
      chmod 444 /target/etc/tuist-rack-node
    - |
      mkdir -p /target/etc/modprobe.d
      cat > /target%[11]s <<'TUIST_EOF'
%[12]s      TUIST_EOF
%[13]s`, s.Host, s.User, s.ConsolePassword, keys.String(), tags, s.TailnetKey, s.TailnetKeyID, s.Role, built,
		indent(handover(fmt.Sprintf("grep -qx 'tailnet_key=%s' /run/tuist-prev/etc/tuist-rack-node 2>/dev/null", s.TailnetKeyID),
			"this installer already installed "+s.Host), "      "),
		ModprobePath, indent(ModprobeConf, "      "), hostKey), nil
}

// handover boots the rack install on this machine's disks that match selects
// (a command run with the install's root at /run/tuist-prev) through BootNext,
// with the installed system's own efibootmgr, instead of installing again.
func handover(match, reason string) string {
	return `mkdir -p /run/tuist-prev
for part in $(lsblk -rpno NAME,FSTYPE | awk '$2 == "ext4" {print $1}'); do
  mount -o ro "$part" /run/tuist-prev 2>/dev/null || continue
  if ` + match + `; then
    for fs in dev proc sys; do mount --rbind "/$fs" "/run/tuist-prev/$fs"; done
    entry=$(chroot /run/tuist-prev efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} [Uu]buntu.*/\1/p' | head -n 1)
    [ -n "$entry" ] && chroot /run/tuist-prev efibootmgr -q -n "$entry"
    echo "tuist: ` + reason + `; booting the installed system" >/dev/console
    umount -R /run/tuist-prev
    reboot -f
  fi
  umount /run/tuist-prev
done
`
}

func indent(s, prefix string) string {
	lines := strings.SplitAfter(s, "\n")
	var b strings.Builder
	for _, line := range lines {
		if line != "" {
			b.WriteString(prefix + line)
		}
	}
	return b.String()
}

// MetaData renders the seed's meta-data. The instance ID changes with every
// install, so cloud-init treats each one as a new instance.
func MetaData(s Seed) string {
	return fmt.Sprintf("instance-id: %s-%s\nlocal-hostname: %s\n", s.Host, strings.ToLower(s.TailnetKeyID), s.Host)
}

// MACPath is a MAC address with hyphens, the form a Secret key or URL path
// can carry.
func MACPath(mac string) string {
	return strings.ReplaceAll(strings.ToLower(mac), ":", "-")
}

// IPXEScript netboots the Ubuntu installer with the host's seed. iPXE runs it
// after the firmware's PXE loads iPXE, and fetches the kernel and initrd from
// server over HTTP; the installer then downloads the ISO into memory (url=) and
// the seed. BOOTIF keeps the installer's DHCP on the NIC that netbooted, and
// cloud-config-url is cleared because cloud-init would otherwise fetch the ISO
// as a config. Under Secure Boot, Ubuntu's shim from the ISO verifies the
// kernel; iPXE skips it otherwise.
func IPXEScript(server, mac string) string {
	server = strings.TrimRight(server, "/")
	return fmt.Sprintf(`#!ipxe
kernel %[1]s/ubuntu/vmlinuz initrd=initrd ip=dhcp BOOTIF=01-%[2]s url=%[1]s/ubuntu/ubuntu.iso cloud-config-url=/dev/null autoinstall ds=nocloud-net;s=%[1]s/hosts/%[2]s/ ---
initrd --name initrd %[1]s/ubuntu/initrd
shim %[1]s/ubuntu/shimx64.efi
boot
`, server, MACPath(mac))
}
