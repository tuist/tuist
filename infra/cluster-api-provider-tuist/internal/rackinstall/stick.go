package rackinstall

import (
	"fmt"
	"regexp"
)

// StickMarker is the file an install stick carries in its seed directory, by
// which the operator tells it from any other USB disk.
const StickMarker = "tuist-install-stick"

var stickServerPattern = regexp.MustCompile(`^http://[A-Za-z0-9.-]+(:[0-9]+)?$`)

type stickPaths struct {
	Seed, Autoinstall, Console, Sys, Node string
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
	script := stickScript(server, stickPaths{Seed: "/run/tuist-user-data", Autoinstall: "/autoinstall.yaml", Console: "/dev/console", Sys: "/sys", Node: "/run/tuist-rack-node"})
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

// stickScript is the stick's early-command. The installer reads
// /autoinstall.yaml again once its early-commands have run, so copying the
// published seed there makes it the install. While nothing is published, it
// announces the machine's SMBIOS identity, NICs and TPM endorsement key to the
// boot server once a minute.
func stickScript(server string, p stickPaths) string {
	return `server='` + server + `'
node='` + p.Node + `'
say() { echo "tuist: $*" >>` + p.Console + `; }
fetch_node() {
  [ -x "$node" ] && return 0
  curl -fsS --max-time 120 -o "$node.new" "$server/tools/rack-node" 2>/dev/null && chmod 755 "$node.new" && mv "$node.new" "$node"
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
      printf 'nic=%s %s %s\n' "$(cat "$nic/address")" "$(basename "$(readlink "$nic/device/driver")")" "$(cat "$nic/device/device")"
    done
    ek=$("$node" ek) && [ -n "$ek" ] && printf 'ek=%s\n' "$ek"
  } 2>/dev/null | curl -fsS --max-time 10 --data-binary @- "$server/cgi-bin/announce" >/dev/null 2>&1 || true
}
waited=0
while :; do
  answered=0 code=1
  macs=$(ip -o link show | awk '{for (i = 1; i < NF; i++) if ($i == "link/ether") print $(i + 1)}' | tr 'A-F:' 'a-f-')
  if fetch_node; then
    mac=$("$node" seed --server "$server" --out ` + p.Seed + ` $macs 2>` + p.Seed + `.err)
    code=$?
  fi
  case "$code" in 0|4) answered=1 ;; esac
  if [ "$code" = 0 ]; then
    id=$(sed -n 's/^# tuist-install-id: \([A-Za-z0-9]*\)$/\1/p' ` + p.Seed + `)
    if [ -n "$id" ]; then
` + indent(handover(`grep -qx "tailnet_key=$id" /run/tuist-prev/etc/tuist-rack-node 2>/dev/null`,
		"this machine already runs the install published for it"), "      ") + `      cp ` + p.Seed + ` ` + p.Autoinstall + `
      say "installing what $server publishes for $mac"
      exit 0
    fi
  fi
  if [ "$answered" = 1 ] || [ "$waited" -ge 300 ]; then
` + indent(handover(`grep -q '^tailnet_key=' /run/tuist-prev/etc/tuist-rack-node 2>/dev/null`,
		"no install is published for this machine"), "    ") + `  fi
  if [ $((waited % 60)) -eq 0 ]; then
    say "waiting for $server to publish an install for this machine"
    [ ! -s ` + p.Seed + `.err ] || say "$(tail -n 1 ` + p.Seed + `.err)"
    announce
  fi
  sleep 10
  waited=$((waited + 10))
done
`
}
