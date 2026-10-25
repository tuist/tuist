package rackinstall

import (
	"fmt"
	"net"
	"regexp"
)

// The preinstall image is what a server vendor boots once on a new box before
// it ships: the install stick's installer, written onto the box's own boot
// drive as a partition that boots on its own, so a box arrives at a site
// already carrying its installer and needs no stick. It carries no credential;
// the box earns its install by attesting with its TPM.
//
// The ISO holds two seeds. The deploy seed, in /nocloud, is what the vendor
// boots: it writes the installer partition and powers the box off. The
// resident seed, in /tuist/resident, is what that partition boots from then
// on.

const (
	// InstallerLabel is the FAT label of the installer partition, by which its
	// GRUB entry tells casper where its live system is.
	InstallerLabel = "TUISTINST"
	// InstallerPartLabel is its GPT partition name.
	InstallerPartLabel = "tuist-installer"
	// InstallerBootEntry is its UEFI boot entry.
	InstallerBootEntry = "tuist installer"
	// InstallerSize is its size, enough for the Ubuntu live server ISO's tree.
	InstallerSize = "4GiB"
	// ResidentSeedDir is where the ISO carries the resident seed.
	ResidentSeedDir = "tuist/resident"

	// residentBootOptions are the resident installer's kernel options.
	residentBootOptions = "live-media=/dev/disk/by-label/" + InstallerLabel + " nopersistent toram"
)

type deployPaths struct {
	// Consoles are written to, the screen and the serial console a BMC's
	// serial-over-LAN reads, each that exists.
	// Run holds scratch files, Tools what is run: Ubuntu mounts /run noexec.
	Cdrom, Consoles, Sys, Mount, PartDir, Run, Tools string
}

// PreinstallDeployUserData renders the deploy seed's user-data.
func PreinstallDeployUserData() string {
	script := deployScript(deployPaths{Cdrom: "/cdrom", Consoles: "/dev/console /dev/ttyS1", Sys: "/sys", Mount: "/run/tuist-installer", PartDir: "/dev/disk/by-partlabel", Run: "/run", Tools: "/usr/local/lib"})
	return "#cloud-config\nautoinstall:\n  version: 1\n  early-commands:\n    - |\n" + indent(script, "      ")
}

// deployScript writes the installer partition onto the box's boot drive: the
// smallest internal disk of at least 100 GB, which on a storage node leaves
// the data drive alone. It refuses a drive holding anything but an installer
// partition, so booting the image by mistake on a running host destroys
// nothing. It copies the live medium, checks the copy against the medium's
// md5sum.txt, swaps in the resident seed, points GRUB's casper at the
// partition, adds the boot entry first in BootOrder, and prints the unit sheet
// a vendor puts on its acceptance report: identity, NICs and the TPM's check
// code, the first 64 bits of its endorsement key's SHA-256. The full
// fingerprint is the one RackLinuxHost status.tpm carries.
func deployScript(p deployPaths) string {
	return `set -u
cdrom='` + p.Cdrom + `' mnt='` + p.Mount + `' sys='` + p.Sys + `'
part='` + p.PartDir + `/` + InstallerPartLabel + `'
consoles='` + p.Consoles + `'
show() { for c in $consoles; do [ -w "$c" ] && cat "$1" >>"$c"; done; cat "$1"; }
say() { echo "tuist: $*" >` + p.Run + `/tuist-say; show ` + p.Run + `/tuist-say; }
fail() { say "DEPLOY FAILED: $*"; say "nothing more happens; power the machine off"; while :; do sleep 3600; done; }

src=$(findmnt -no SOURCE "$cdrom")
srcdisk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n 1)
[ -n "$srcdisk" ] || srcdisk=$(basename "$src")
# casper takes the first live medium it finds, which can be an installer
# partition this image wrote before rather than the image itself.
[ "$(lsblk -no LABEL "$src" 2>/dev/null)" != ` + InstallerLabel + ` ] ||
  fail "this booted the installer partition on $src instead of the image; wipe /dev/$srcdisk and boot the image again"
target=$(lsblk -dbnpo NAME,SIZE,TYPE,RM,TRAN | awk -v s="/dev/$srcdisk" \
  '$3 == "disk" && $4 == 0 && $1 != s && $2 >= 100000000000 && $5 != "usb" {print $2, $1}' | sort -n | head -n 1 | cut -d' ' -f2)
[ -n "$target" ] || fail "no internal disk of at least 100 GB"
say "boot drive: $target"

parts=$(lsblk -nro TYPE "$target" | grep -c '^part$')
labels=$(lsblk -nro LABEL "$target" | grep -v '^$' | sort -u | tr '\n' ' ')
if [ "$parts" -gt 0 ] || [ -n "$(wipefs -n "$target" 2>/dev/null | tail -n +2)" ]; then
  [ "$parts" = 1 ] && [ "$labels" = "` + InstallerLabel + ` " ] || fail "$target is not blank ($parts partitions, labels: ${labels:-none}); wipe it and boot this image again"
  say "$target holds an installer partition; replacing it"
fi

sgdisk --zap-all "$target" >/dev/null 2>&1
sgdisk -n 1:1MiB:+` + InstallerSize + ` -t 1:EF00 -c 1:` + InstallerPartLabel + ` "$target" >/dev/null || fail "partitioning $target"
partprobe "$target" 2>/dev/null
udevadm settle
[ -e "$part" ] || fail "no $part after partitioning"
mkfs.vfat -F 32 -n ` + InstallerLabel + ` "$part" >/dev/null || fail "formatting $part"
mkdir -p "$mnt" && mount "$part" "$mnt" || fail "mounting $part"

say "copying the installer to $part"
(cd "$cdrom" && tar --exclude=./ubuntu --exclude=./dists/stable --exclude=./dists/unstable -cf - .) |
  (cd "$mnt" && tar --no-same-owner --no-same-permissions -xf - 2>/dev/null)
(cd "$mnt" && md5sum -c --quiet md5sum.txt) || fail "the copy on $part does not match md5sum.txt"
rm -rf "$mnt/nocloud" && mv "$mnt/` + ResidentSeedDir + `" "$mnt/nocloud" || fail "installing the resident seed"
# casper boots from the partition alone, and keeps no persistence on the
# drive: it would otherwise fill the free space the install goes into. It
# runs from a copy in memory, since the installer refuses the disk its live
# medium is on.
sed -i 's| nopersistent ---| ---|; s|---|` + residentBootOptions + ` ---|' "$mnt/boot/grub/grub.cfg"
sync

# The live system lacks efibootmgr, but has its libraries, and the medium's
# pool carries it.
efi='` + p.Tools + `/tuist-efibootmgr'
dpkg -x "$(ls "$cdrom"/pool/main/e/efibootmgr/efibootmgr_*_amd64.deb | head -n 1)" "$efi" || fail "unpacking efibootmgr from the medium"
efibootmgr=$(ls "$efi"/bin/efibootmgr "$efi"/usr/bin/efibootmgr 2>/dev/null | head -n 1)
"${efibootmgr:-missing}" -q -c -d "$target" -p 1 -L '` + InstallerBootEntry + `' -l '\EFI\boot\bootx64.efi' || fail "adding the boot entry"

dmi="$sys/class/dmi/id"
ek=$("$cdrom/tuist/rack-node" ek 2>/dev/null)
fp=$(printf %s "$ek" | base64 -d 2>/dev/null | sha256sum | cut -c1-64)
[ -n "$ek" ] || fp=
{
  echo "tuist unit sheet"
  echo "product: $(cat "$dmi/sys_vendor") $(cat "$dmi/product_name")"
  echo "serial: $(cat "$dmi/product_serial")"
  echo "uuid: $(tr 'A-F' 'a-f' <"$dmi/product_uuid")"
  for nic in "$sys"/class/net/*; do
    [ -e "$nic/device/driver" ] || continue
    case "$(basename "$(readlink "$nic/device/driver")")" in ` + usbNICDrivers + `) continue ;; esac
    echo "nic: $(cat "$nic/address") $(basename "$(readlink "$nic/device/driver")") $(basename "$nic")"
  done
  if [ -n "$fp" ]; then
    echo "tpm ek sha256: $fp"
    echo "tpm check code: $(echo "$fp" | cut -c1-16 | sed 's/..../&-/g; s/-$//')"
  else
    echo "tpm: NONE FOUND"
  fi
} >"$mnt/tuist/unit-sheet.txt"
show "$mnt/tuist/unit-sheet.txt"
umount "$mnt"
say "DEPLOY OK; powering off in 60 seconds"
sleep 60
poweroff -f
`
}

// ResidentUserData renders the resident seed: the install stick's installer,
// asking each of servers in turn for the install published for the machine,
// the site's boot server first and the internet's after it, and taking a
// site's static WAN when nothing gave it a default route. An internet boot
// server hands a seed only to a machine that attests with its pinned TPM.
func ResidentUserData(servers []string, wans []StaticWAN) (string, error) {
	if len(servers) == 0 {
		return "", fmt.Errorf("a resident installer needs a boot server to ask")
	}
	for _, s := range servers {
		if !stickServerPattern.MatchString(s) && !residentServerPattern.MatchString(s) {
			return "", fmt.Errorf("%q is not a boot server's http:// address or an https:// one", s)
		}
	}
	for _, w := range wans {
		if !wanSitePattern.MatchString(w.Site) || net.ParseIP(w.Gateway).To4() == nil || w.VLAN < 1 || w.VLAN > 4094 {
			return "", fmt.Errorf("static WAN %+v is not a site, an IPv4 gateway and a VLAN", w)
		}
		if _, _, err := net.ParseCIDR(w.Address); err != nil {
			return "", fmt.Errorf("static WAN of %s: %w", w.Site, err)
		}
	}
	script := stickScript(stickConfig{Servers: servers, WANs: wans}, stickPaths{Seed: "/run/tuist-user-data", Autoinstall: "/autoinstall.yaml", Console: "/dev/console", Sys: "/sys", Node: "/usr/local/bin/tuist-rack-node", Uptime: "/proc/uptime", Medium: "/cdrom", Dev: "/dev"})
	return "#cloud-config\nautoinstall:\n  version: 1\n  early-commands:\n    - |\n" + indent(script, "      "), nil
}

var (
	residentServerPattern = regexp.MustCompile(`^https://[A-Za-z0-9.-]+(:[0-9]+)?$`)
	wanSitePattern        = regexp.MustCompile(`^[a-z0-9-]+$`)
)
