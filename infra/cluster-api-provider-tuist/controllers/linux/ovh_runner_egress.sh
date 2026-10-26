#!/usr/bin/env bash
set -euo pipefail
sudo bash -s <<'TUIST_RUNNER_EGRESS_ROOT'
set -euo pipefail
install -d -m 0755 /etc/tuist /usr/local/sbin /etc/systemd/system/kubelet.service.d
exec 8>/run/lock/tuist-runner-egress.lock
flock 8
identity='@MAC@ @ADDRESS@'
state=/etc/tuist/runner-egress
if [ -f "$state" ] && [ "$(cat "$state")" != "$identity" ]; then
 echo 'refusing to replace another runner egress address' >&2
 exit 1
fi
iface=
for path in /sys/class/net/*/address; do
 if [ "$(cat "$path")" = '@MAC@' ]; then iface=$(basename "$(dirname "$path")"); break; fi
done
[ -n "$iface" ] || { echo 'runner vRack NIC missing' >&2; exit 1; }
if ip -4 route show default | grep -Eq "(^| )dev $iface( |$)"; then
 echo 'refusing to configure primary default-route interface' >&2
 exit 1
fi
if [ ! -f "$state" ] && ip -o -4 address show dev "$iface" | grep -Fq ' @ADDRESS@/32 '; then
 echo 'refusing to take ownership of an existing address' >&2
 exit 1
fi
# Table and priority are dedicated to this feature. Never flush foreign routes.
foreign_routes=$(ip -4 route show table 243 2>/dev/null | grep -v ' proto 243' || true)
[ -z "$foreign_routes" ] || { echo 'runner routing table already in use' >&2; exit 1; }
rules=$(ip -4 rule show priority 10430)
if [ -n "$rules" ] && [ "$rules" != "10430:$(printf '\t')from @ADDRESS@ lookup 243" ]; then
 echo 'runner rule priority already in use' >&2
 exit 1
fi
if [ '@MODE@' = remove ]; then
 # An explicit stop propagates through Requires even for an inactive oneshot.
 # Detach and reload first so withdrawing egress cannot stop kubelet.
 rm -f /etc/systemd/system/kubelet.service.d/35-runner-egress.conf
 systemctl daemon-reload
 # Stop the repair loop before removing its state. Retain intent on any error.
 if [ -f /etc/systemd/system/tuist-runner-egress.timer ]; then
  systemctl disable --now tuist-runner-egress.timer
 fi
 if [ -f /etc/systemd/system/tuist-runner-egress.service ]; then
  systemctl stop tuist-runner-egress.service
 fi
 if [ -n "$rules" ]; then ip -4 rule del priority 10430 from '@ADDRESS@/32' table 243; fi
 if [ -n "$(ip -4 route show table 243 2>/dev/null)" ]; then
  ip -4 route flush table 243 proto 243
 fi
 if ip -o -4 address show dev "$iface" | grep -Fq ' @ADDRESS@/32 '; then
  ip address del '@ADDRESS@/32' dev "$iface"
 fi
 [ -z "$(ip -4 rule show priority 10430)" ]
 [ -z "$(ip -4 route show table 243 2>/dev/null)" ]
 if ip -o -4 address show dev "$iface" | grep -Fq ' @ADDRESS@/32 '; then exit 1; fi
 rm -f /etc/systemd/system/kubelet.service.d/35-runner-egress.conf \
  /etc/systemd/system/tuist-runner-egress.service /etc/systemd/system/tuist-runner-egress.timer \
  /usr/local/sbin/tuist-runner-egress "$state"
 systemctl daemon-reload
 exit 0
fi
# Persist ownership before touching Linux so an interrupted SSH call is removable.
printf '%s\n' "$identity" > "$state.new"
mv "$state.new" "$state"
cat > /usr/local/sbin/tuist-runner-egress.new <<'TUIST_RUNNER_EGRESS_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
exec 9>/run/lock/tuist-runner-egress.lock
flock 9
[ "$(cat /etc/tuist/runner-egress)" = '@MAC@ @ADDRESS@' ]
iface=
for path in /sys/class/net/*/address; do
 if [ "$(cat "$path")" = '@MAC@' ]; then iface=$(basename "$(dirname "$path")"); break; fi
done
[ -n "$iface" ] || { echo 'runner vRack NIC missing' >&2; exit 1; }
if ip -4 route show default | grep -Eq "(^| )dev $iface( |$)"; then exit 1; fi
foreign_routes=$(ip -4 route show table 243 2>/dev/null | grep -v ' proto 243' || true)
[ -z "$foreign_routes" ] || { echo 'runner routing table already in use' >&2; exit 1; }
rules=$(ip -4 rule show priority 10430)
if [ -n "$rules" ] && [ "$rules" != "10430:$(printf '\t')from @ADDRESS@ lookup 243" ]; then exit 1; fi
ip link set dev "$iface" up
ip address replace '@ADDRESS@/32' dev "$iface" noprefixroute
echo 2 > "/proc/sys/net/ipv4/conf/$iface/rp_filter"
ip -4 route replace '@GATEWAY@/32' dev "$iface" scope link table 243 proto 243
ip -4 route replace default via '@GATEWAY@' dev "$iface" src '@ADDRESS@' table 243 proto 243
if [ -z "$rules" ]; then ip -4 rule add priority 10430 from '@ADDRESS@/32' table 243; fi
ip -4 route get 1.1.1.1 from '@ADDRESS@' | grep -F "via @GATEWAY@ dev $iface" | grep -Fq 'table 243'
TUIST_RUNNER_EGRESS_SCRIPT
chmod 0755 /usr/local/sbin/tuist-runner-egress.new
mv /usr/local/sbin/tuist-runner-egress.new /usr/local/sbin/tuist-runner-egress
cat > /etc/systemd/system/tuist-runner-egress.service <<'TUIST_RUNNER_EGRESS_SERVICE'
[Unit]
Description=OVH runner vRack source routing
Wants=network-online.target
After=network-online.target
Before=kubelet.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/tuist-runner-egress
TUIST_RUNNER_EGRESS_SERVICE
cat > /etc/systemd/system/kubelet.service.d/35-runner-egress.conf <<'TUIST_RUNNER_EGRESS_KUBELET'
[Unit]
Requires=tuist-runner-egress.service
After=tuist-runner-egress.service
TUIST_RUNNER_EGRESS_KUBELET
cat > /etc/systemd/system/tuist-runner-egress.timer <<'TUIST_RUNNER_EGRESS_TIMER'
[Unit]
Description=Repair OVH runner egress routing drift
[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
[Install]
WantedBy=timers.target
TUIST_RUNNER_EGRESS_TIMER
systemctl daemon-reload
# The service takes the same lock. Release ours before asking systemd to run it.
flock -u 8
systemctl start tuist-runner-egress.service
systemctl enable --now tuist-runner-egress.timer
TUIST_RUNNER_EGRESS_ROOT
