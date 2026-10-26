#!/bin/bash
# PicOS zero-touch bootstrap, rendered by rack:fleet render into the rack-edge
# site files and fetched by a factory switch's ZTP over TFTP (DHCP options 66
# and 67). See infra/rack-switch-fleet/AGENTS.md, "PicOS switches".
#
# It carries no secret: the rack switch controller's public key, the NTP
# servers and the user name are its only parameters. ZTP runs it as root before
# PicOS's CLI exists, so it leaves a post-xorplus hook that, once the CLI is up:
#   - adds the controller's user as a super-user and installs the controller's
#     public key for it (4.7.1M has no CLI path for keys), listed in the user
#     backup list so it survives a reboot,
#   - replaces the passwords of admin and of the controller's user with random
#     ones generated on the switch and never printed, so the factory
#     admin/pica8 login stops working; the controller sets admin's real
#     password when it adopts the switch,
#   - sets the NTP servers and enables NETCONF,
# and commits; then, once the key file exists, turns ZTP's configuration leaf
# off in a second commit, which saves the key into the backup, and disables
# ZTP itself. A failure anywhere leaves ZTP on, so the next boot tries again.
# For a switch whose MAC the site records with a live WAN port, a third commit
# sets up the WAN path; its failure is only logged.
# version and switch_mac come from the switch's own ztp-functions.sh.
# shellcheck disable=SC1091,SC2154
source /usr/bin/ztp-functions.sh

user='tuist'
ntp_servers='162.159.200.1 162.159.200.123'
authorized_keys='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB8YWxzgQuusy9tVUiW51asi86OnNXIkOIToZs6xBgT4 rack-switch-controller'
# The release every step was measured on.
measured='4.7.1M-EC1'

log() { logger -p local0.warning -t rack-ztp -- "$*"; echo "rack-ztp: $*"; }

if [ "$version" != "$measured" ]; then
  log "PicOS $version is not $measured, which this bootstrap was measured on; trying anyway"
fi

stage=/cftmp/auto
worker="$stage/rack-ztp"
keys="$stage/rack-ztp.keys"
mkdir -p "$stage"
printf '%s\n' "$authorized_keys" > "$keys"
chmod 600 "$keys"

cat > "$worker" <<'EOF'
#!/bin/bash
source /usr/bin/ztp-functions.sh
log() { logger -p local0.warning -t rack-ztp -- "$*"; }
user="$1"; ntp_servers="$2"; keys="$3"
random() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; }

for _ in $(seq 60); do
  /pica/bin/pica_sh -c "show version" >/dev/null 2>&1 && break
  sleep 5
done

model="$(/pica/bin/pica_sh -c "show version" 2>/dev/null | tr -d '\r' | awk -F': *' '/^Model/{print $2}')"
commands="configure"
commands+=";set system login user $user class super-user"
commands+=";set system login user $user authentication plain-text-password $(random)"
commands+=";set system login user admin authentication plain-text-password $(random)"
for server in $ntp_servers; do
  commands+=";set system ntp server-ip $server"
done
commands+=";set protocols netconf"
commands+=";commit"

# pica_sh echoes every line it runs, passwords included, so nothing it prints
# is kept.
output="$(/pica/bin/pica_sh -c "$commands" 2>&1 | tr -d '\r')"
unset commands
if ! grep -q '^Commit OK' <<<"$output"; then
  log "commit failed; ZTP stays on for the next boot: $(grep -m1 -E 'ERROR|Failed' <<<"$output" | sed -E 's/plain-text-password [^ .]+/plain-text-password <redacted>/g')"
  exit 1
fi

# The user exists only after that commit. Its key survives a reboot only in a
# backup saved after the file is written and listed, which the second commit
# does.
home="$(getent passwd "$user" | cut -d: -f6)"
group="$(id -gn "$user")"
install -d -m 700 -o "$user" -g "$group" "$home/.ssh"
install -m 600 -o "$user" -g "$group" "$keys" "$home/.ssh/authorized_keys"
rm -f "$keys"
list=/etc/picos/user_backup_files.lst
entry="$home/.ssh/authorized_keys"
grep -qxF "$entry" "$list" 2>/dev/null || echo "$entry" >> "$list"

output="$(/pica/bin/pica_sh -c "configure;set system ztp enable false;commit" 2>&1 | tr -d '\r')"
if ! grep -q '^Commit OK' <<<"$output"; then
  log "second commit failed; ZTP stays on for the next boot: $(grep -m1 -E 'ERROR|Failed' <<<"$output")"
  exit 1
fi

# The WAN path, in a commit of its own so that a failure costs only this: the
# carrier's port untagged on the WAN VLAN and the edges' ports tagged with it,
# as the controller configures them. A factory switch passes the carrier
# untagged, and the controller is reached over that same WAN, so without this
# the first edge of a site loses its way out when its rack-edge pod moves the
# WAN onto the VLAN.
wan_vlan='4001 wan'
wan_paths='649d99d9810e 27 29,30'
# The management port's MAC is the one the edge's DHCP answered, so it is the
# one the site records.
mac="$(tr -d ':-' <<<"$(cat /sys/class/net/eth0/address 2>/dev/null || echo "${switch_mac:-}")" | tr 'A-F' 'a-f')"
if [ -n "$wan_paths" ]; then
  read -r vlan_id vlan_name <<<"$wan_vlan"
  found=""
  while read -r path_mac wan legs; do
    [ -n "$path_mac" ] && [ "$path_mac" = "$mac" ] || continue
    found=1
    commands="configure;set vlans vlan-id $vlan_id vlan-name \"$vlan_name\""
    commands+=";set interface gigabit-ethernet te-1/1/$wan family ethernet-switching native-vlan-id $vlan_id"
    for leg in ${legs//,/ }; do
      commands+=";set interface gigabit-ethernet te-1/1/$leg family ethernet-switching port-mode trunk"
      commands+=";set interface gigabit-ethernet te-1/1/$leg family ethernet-switching vlan members $vlan_id"
    done
    output="$(/pica/bin/pica_sh -c "$commands;commit" 2>&1 | tr -d '\r')"
    if grep -q '^Commit OK' <<<"$output"; then
      log "WAN path: te-1/1/$wan untagged and te-1/1/{$legs} tagged on VLAN $vlan_id"
    else
      log "WAN path commit failed; the controller sets it once it reaches the switch: $(grep -m1 -E 'ERROR|Failed' <<<"$output")"
    fi
  done <<<"$wan_paths"
  [ -n "$found" ] || log "no WAN path recorded for switch ${mac:-of unknown MAC}; the controller sets it once it reaches the switch"
fi

ztp_disable
log "provisioned: user $user, ntp $ntp_servers, netconf on, model ${model:-unknown}; ZTP off"
rm -f "$0"
EOF
chmod 700 "$worker"

# The hook runs as xorplus starts and must not hold it up, and /cftmp/auto is
# in the backup, so it deletes itself.
hook="$stage/post-xorplus"
cat > "$hook" <<EOF
#!/bin/bash
setsid $worker '$user' '$ntp_servers' '$keys' > /dev/null 2>&1 < /dev/null &
rm -f $hook
EOF
chmod a+x "$hook"
chown root:xorp "$hook"
log "staged provisioning for $user (switch $switch_mac, PicOS $version)"
exit 0
