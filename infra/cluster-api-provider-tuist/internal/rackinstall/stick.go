package rackinstall

import (
	"fmt"
	"regexp"
	"strings"
)

// StickMarker is the file an install stick carries in its seed directory, by
// which the operator tells it from any other USB disk.
const StickMarker = "tuist-install-stick"

var stickServerPattern = regexp.MustCompile(`^http://[A-Za-z0-9.-]+(:[0-9]+)?$`)

type stickPaths struct {
	// Medium is the live system's boot medium, which a preinstalled
	// installer partition carries rack-node on.
	Seed, Autoinstall, Console, Sys, Node, Uptime, Medium, Dev string
}

// StickUserData renders the seed of a site's install stick, which carries no
// host's install and no credential. Its installer asks the site's boot server
// (server, the edges' provisioning address) for the install published for one
// of the machine's NICs through rack-node, which it fetches from the boot
// server and which attests with the machine's TPM when the host's is pinned,
// waiting until there is one, and installs that. The boot server hands it to a
// netbooting host whose TPM is pinned in place of the seed. A
// machine with a rack install on its disks, which boots through the stick
// first, gets that install booted instead as soon as the boot server answers
// with nothing published, or after five minutes of not reaching it.
func StickUserData(server string) (string, error) {
	if !stickServerPattern.MatchString(server) {
		return "", fmt.Errorf("%q is not the boot server's http:// address", server)
	}
	script := stickScript(stickConfig{Servers: []string{server}}, stickPaths{Seed: "/run/tuist-user-data", Autoinstall: "/autoinstall.yaml", Console: "/dev/console", Sys: "/sys", Node: "/usr/local/bin/tuist-rack-node", Uptime: "/proc/uptime", Medium: "/cdrom", Dev: "/dev"})
	return "#cloud-config\nautoinstall:\n  version: 1\n  early-commands:\n    - |\n" + indent(script, "      ") +
		"    - |\n" + indent(keepStick, "      "), nil
}

// keepStick stops the live system from ejecting the stick when the install
// reboots (casper-stop, run by casper.service at shutdown): an ejected stick
// has no medium until something loads it again, so the next reinstall could
// not boot it.
const keepStick = `mkdir -p /run/systemd/system/casper.service.d
printf '[Service]\nExecStart=\nExecStart=/bin/true\n' >/run/systemd/system/casper.service.d/tuist-keep-stick.conf
systemctl daemon-reload
`

// StickMetaData renders the stick seed's meta-data.
func StickMetaData() string {
	return "instance-id: tuist-install-stick\n"
}

// StickNetworkConfig asks for DHCP on every wired port of the installer, so
// the port on the rack's management segment reaches the boot server whichever
// ports have links.
func StickNetworkConfig() string {
	return `version: 2
ethernets:
  wired:
    match:
      name: "e*"
    dhcp4: true
    optional: true
`
}

// stickConfig is what a stick's early-command asks and how it gets a way out.
type stickConfig struct {
	// Servers are the boot servers it asks in turn: the site's provisioning
	// address, and for an installer that may be the first box of a site, the
	// internet's.
	Servers []string
	// WANs are the sites' static uplinks it tries when nothing gave it a
	// default route.
	WANs []StaticWAN
}

// StaticWAN is a site's static uplink: its address with prefix, its gateway,
// and the VLAN the carrier's handoff arrives on once the site's switches are
// configured. A factory switch passes it untagged.
type StaticWAN struct {
	Site    string
	Address string
	Gateway string
	VLAN    int
}

// stickScript is the stick's early-command. The installer reads
// /autoinstall.yaml again once its early-commands have run, so copying the
// published seed there makes it the install. While nothing is published, it
// announces the machine's SMBIOS identity, NICs and TPM endorsement key to the
// boot servers once a minute.
//
// Its five minutes are on the clock, since a pass that cannot reach the boot
// server takes longer than its ten seconds' sleep: without its provisioning
// lease the machine sends the connection out the default route an uplink's
// DHCP gave it, where nothing answers, and only the connect timeout ends it.
//
// A machine with no default route, as the first edge of a site, whose uplink
// is the carrier's static handoff, tries each site's static WAN on each port
// with a link, untagged and on the site's VLAN, taking it only when no one
// answers for the address and its gateway does.
func stickScript(c stickConfig, p stickPaths) string {
	wans := ""
	for _, w := range c.WANs {
		wans += fmt.Sprintf("%s %s %s %d\n", w.Site, w.Address, w.Gateway, w.VLAN)
	}
	return `servers='` + strings.Join(c.Servers, " ") + `'
server=${servers%% *}
node='` + p.Node + `'
wans='` + wans + `'
say() { echo "tuist: $*" >>` + p.Console + `; }
uptime() { cut -d. -f1 ` + p.Uptime + `; }
fetch_node() {
  [ -x "$node" ] && return 0
  if [ -f ` + p.Medium + `/tuist/rack-node ]; then
    cp ` + p.Medium + `/tuist/rack-node "$node" && chmod 755 "$node" && return 0
  fi
  for s in $servers; do
    curl -fsS --connect-timeout 10 --max-time 120 -o "$node.new" "$s/tools/rack-node" 2>/dev/null && chmod 755 "$node.new" && mv "$node.new" "$node" && return 0
  done
  return 1
}
announce() {
  dmi=` + p.Sys + `/class/dmi/id
  {
    printf 'uuid=%s\n' "$(tr 'A-F' 'a-f' <"$dmi/product_uuid")"
    serial=$(tr -cd 'A-Za-z0-9._-' <"$dmi/product_serial" | head -c 64)
    [ -z "$serial" ] || printf 'serial=%s\n' "$serial"
    product=$(cat "$dmi/sys_vendor" "$dmi/product_name" 2>/dev/null | tr '\n' ' ' | tr -cd ' -~' | sed 's/ *$//' | head -c 64)
    [ -z "$product" ] || printf 'product=%s\n' "$product"
    for nic in ` + p.Sys + `/class/net/*; do
      [ -e "$nic/device/driver" ] || continue
      case "$(basename "$(readlink "$nic/device/driver")")" in ` + usbNICDrivers + `) continue ;; esac
      printf 'nic=%s %s %s\n' "$(cat "$nic/address")" "$(basename "$(readlink "$nic/device/driver")")" "$(cat "$nic/device/device")"
    done
    ek=$("$node" ek) && [ -n "$ek" ] && printf 'ek=%s\n' "$ek"
  } 2>/dev/null >` + p.Seed + `.announce
  for s in $servers; do
    curl -fsS --max-time 10 --data-binary @- "$s/cgi-bin/announce" <` + p.Seed + `.announce >/dev/null 2>&1 || true
  done
}
static_wan() {
  [ -n "$wans" ] && [ ! -s ` + p.Seed + `.wan ] || return 0
  [ -z "$(ip -4 route show default)" ] || return 0
  echo "$wans" | while read -r site addr gw vlan; do
    [ -n "$site" ] || continue
    for nic in ` + p.Sys + `/class/net/*; do
      [ -e "$nic/device" ] && [ "$(cat "$nic/carrier" 2>/dev/null)" = 1 ] || continue
      nic=$(basename "$nic")
      for tag in 0 "$vlan"; do
        dev=$nic
        if [ "$tag" != 0 ]; then
          dev=$nic.$tag
          ip link add link "$nic" name "$dev" type vlan id "$tag" 2>/dev/null || continue
        fi
        ip link set "$dev" up
        if busybox arping -D -q -c 2 -w 3 -I "$dev" "${addr%/*}" && ip addr add "$addr" dev "$dev"; then
          if busybox arping -q -c 2 -w 3 -I "$dev" "$gw" && ip route add default via "$gw" dev "$dev"; then
            resolvectl dns "$dev" 1.1.1.1 8.8.8.8 2>/dev/null
            echo "$site $dev $addr $gw" >` + p.Seed + `.wan
            say "took $site's static WAN $addr on $dev, through $gw"
            exit 0
          fi
          ip addr del "$addr" dev "$dev"
        fi
        [ "$tag" = 0 ] || ip link del "$dev"
      done
    done
  done
}
resident_layout() {
  grep -q '` + InstallerRestPlaceholder + `' "$1" || return 0
  inst=$(readlink -f ` + p.Dev + `/disk/by-label/` + InstallerLabel + `)
  if [ ! -e "$inst" ]; then
    say "the install keeps an installer partition this machine does not have"
    return 1
  fi
  disk=/dev/$(lsblk -no PKNAME "$inst")
  for n in $(sgdisk -p "$disk" | awk '$1 ~ /^[0-9]+$/ && $1 != 1 {print $1}'); do
    sgdisk -d "$n" "$disk" >/dev/null || return 1
  done
  partprobe "$disk" 2>/dev/null
  udevadm settle
  rest=$((($(lsblk -bdno SIZE "$disk") / 1048576 - 1 - 4096 - 1024 - 2048 - 2) * 1048576))
  sed -i "s|` + InstallerDiskPlaceholder + `|$disk|; s|` + InstallerRestPlaceholder + `|$rest|" "$1"
}
started=$(uptime) said=""
while :; do
  static_wan
  answered=0 code=1
  macs=$(ip -o link show | awk '{for (i = 1; i < NF; i++) if ($i == "link/ether") print $(i + 1)}' | tr 'A-F:' 'a-f-')
  if fetch_node; then
    for server in $servers; do
      mac=$("$node" seed --server "$server" --out ` + p.Seed + ` $macs 2>` + p.Seed + `.err)
      code=$?
      case "$code" in 0) answered=1; break ;; 4) answered=1 ;; esac
    done
  fi
  if [ "$code" = 0 ]; then
    id=$(sed -n 's/^# tuist-install-id: \([A-Za-z0-9]*\)$/\1/p' ` + p.Seed + `)
    if [ -n "$id" ]; then
` + indent(handover(`grep -qx "tailnet_key=$id" /run/tuist-prev/etc/tuist-rack-node 2>/dev/null`,
		"this machine already runs the install published for it"), "      ") + `      if resident_layout ` + p.Seed + `; then
        cp ` + p.Seed + ` ` + p.Autoinstall + `
        say "installing what $server publishes for $mac"
        exit 0
      fi
    fi
  fi
  waited=$(($(uptime) - started))
  if [ "$answered" = 1 ] || [ "$waited" -ge 300 ]; then
` + indent(handover(`grep -q '^tailnet_key=' /run/tuist-prev/etc/tuist-rack-node 2>/dev/null`,
		"no install is published for this machine"), "    ") + `  fi
  if [ -z "$said" ] || [ $((waited - said)) -ge 60 ]; then
    said=$waited
    say "waiting for $(echo $servers | sed 's/ / or /g') to publish an install for this machine"
    [ "$answered" = 1 ] || say "no answer from $(echo $servers | sed 's/ / or /g'); addresses: $(ip -4 -o addr show scope global | awk '{printf "%s %s; ", $2, $4}')"
    [ ! -s ` + p.Seed + `.err ] || say "$(tail -n 1 ` + p.Seed + `.err)"
    announce
  fi
  sleep 10
done
`
}

// usbNICDrivers are the drivers of USB network devices, which are no NIC of
// the machine's: the BMC's Redfish host interface (cdc_ether on the ASUS
// RS501A), whose MAC is the BMC's to change.
const usbNICDrivers = "cdc_ether|cdc_ncm|rndis_host"
