package linux

import (
	"context"
	"crypto/sha256"
	"fmt"
	"net/netip"
	"sort"
	"strings"

	corev1 "k8s.io/api/core/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	VRackReadyCondition          clusterv1.ConditionType = "VRackReady"
	vrackReleaseStartedCondition clusterv1.ConditionType = "VRackReleaseStarted"
	vrackConfigAnnotation                                = "tuist.dev/vrack-config"
	vrackReadyLabel                                      = "tuist.dev/vrack-ready"
)

// Reserve before touching a host, under the same leader-local lock as adoption.
// An uncached read makes sibling reconciles observe the reservation immediately.
func (r *OVHDedicatedMachineReconciler) reserveVRackAddress(ctx context.Context, machine *infrav1.OVHDedicatedMachine) error {
	r.adoptMu.Lock()
	defer r.adoptMu.Unlock()
	list := &infrav1.OVHDedicatedMachineList{}
	if err := r.reader().List(ctx, list); err != nil {
		return err
	}
	address, err := allocateVRackAddress(machine, list.Items)
	if err != nil || address == machine.Status.VRackAddress {
		return err
	}
	reserved := machine.DeepCopy()
	reserved.Status.VRackAddress = address
	if err := r.Status().Patch(ctx, reserved, client.MergeFrom(machine)); err != nil {
		return err
	}
	// Do not expose an uncommitted reservation to Reconcile's deferred patch:
	// after a failed write, a sibling may already have claimed that address.
	machine.Status.VRackAddress = address
	machine.ResourceVersion = reserved.ResourceVersion
	return nil
}

func allocateVRackAddress(machine *infrav1.OVHDedicatedMachine, machines []infrav1.OVHDedicatedMachine) (string, error) {
	prefix, err := netip.ParsePrefix(machine.Spec.VRackCIDR)
	if err != nil || !prefix.Addr().Is4() || !prefix.Addr().IsPrivate() || prefix.Bits() < 24 || prefix.Bits() > 28 || prefix != prefix.Masked() {
		return "", fmt.Errorf("vRackCIDR must be a canonical private IPv4 /24 through /28")
	}
	used := map[string]bool{}
	for _, peer := range machines {
		if peer.Spec.VRackID != machine.Spec.VRackID {
			continue
		}
		if peer.Spec.VRackCIDR != machine.Spec.VRackCIDR || peer.Namespace != machine.Namespace {
			return "", fmt.Errorf("vRack %s must have one namespace and CIDR", machine.Spec.VRackID)
		}
		if peer.Name != machine.Name && peer.Status.VRackAddress != "" {
			used[peer.Status.VRackAddress] = true
		}
	}
	if machine.Status.VRackAddress != "" {
		address, err := netip.ParseAddr(machine.Status.VRackAddress)
		if err != nil || !prefix.Contains(address) || !prefix.Contains(address.Next()) || address.Compare(prefix.Addr().Next()) <= 0 || used[address.String()] {
			return "", fmt.Errorf("reserved vRack address is invalid or duplicated; restore the original network configuration")
		}
		return address.String(), nil
	}
	// Reserve network, broadcast and .1 (operator diagnostics). Deleting
	// Machines still hold their address until their release reinstall finishes.
	for address := prefix.Addr().Next().Next(); prefix.Contains(address.Next()); address = address.Next() {
		if !used[address.String()] {
			return address.String(), nil
		}
	}
	return "", fmt.Errorf("vRack address pool %s is exhausted", prefix)
}

type vrackRoute struct {
	Public  string
	Private string
}

func vrackRoutes(machine *infrav1.OVHDedicatedMachine, machines []infrav1.OVHDedicatedMachine) []vrackRoute {
	routes := []vrackRoute{}
	for _, peer := range machines {
		if peer.Name == machine.Name || peer.Namespace != machine.Namespace || peer.Spec.VRackID != machine.Spec.VRackID ||
			peer.Spec.VRackCIDR != machine.Spec.VRackCIDR || !peer.DeletionTimestamp.IsZero() || !conditions.IsTrue(&peer, VRackReadyCondition) {
			continue
		}
		public := ovhPublicAddress(&peer)
		private, err := netip.ParseAddr(peer.Status.VRackAddress)
		if public != "" && err == nil && private.Is4() {
			routes = append(routes, vrackRoute{Public: public, Private: private.String()})
		}
	}
	sort.Slice(routes, func(i, j int) bool { return routes[i].Public < routes[j].Public })
	return routes
}

func ovhPublicAddress(machine *infrav1.OVHDedicatedMachine) string {
	for _, address := range machine.Status.Addresses {
		if address.Type == clusterv1.MachineExternalIP {
			if ip, err := netip.ParseAddr(address.Address); err == nil && ip.Is4() {
				return ip.String()
			}
		}
	}
	return ""
}

func (r *OVHDedicatedMachineReconciler) reconcileVRack(ctx context.Context, machine *infrav1.OVHDedicatedMachine, node *corev1.Node) (err error) {
	if machine.Spec.VRackID == "" && machine.Status.VRackAddress == "" {
		return nil
	}
	defer func() {
		if err != nil {
			conditions.MarkFalse(machine, VRackReadyCondition, "VRackConfigurationFailed", clusterv1.ConditionSeverityError, "%s", err)
		}
		if conditions.IsFalse(machine, VRackReadyCondition) && node.Labels[vrackReadyLabel] == "true" {
			before := node.DeepCopy()
			delete(node.Labels, vrackReadyLabel)
			if patchErr := r.Patch(ctx, node, client.MergeFrom(before)); patchErr != nil && err == nil {
				err = patchErr
			}
		}
	}()
	if machine.Spec.VRackID == "" {
		return fmt.Errorf("removing vRack from an addressed machine requires replacement; restore vRackID")
	}
	if err := r.reserveVRackAddress(ctx, machine); err != nil {
		return err
	}
	mac, attached, err := r.OVHClient.EnsureVRack(ctx, machine.Status.ServiceName, machine.Spec.VRackID)
	if err != nil {
		return err
	}
	if !attached {
		conditions.MarkFalse(machine, VRackReadyCondition, "VRackAttaching", clusterv1.ConditionSeverityInfo, "waiting for OVH to attach the private NIC")
		return nil
	}
	public := ovhPublicAddress(machine)
	if public == "" {
		return fmt.Errorf("vRack configuration requires the machine's public IPv4 address")
	}
	list := &infrav1.OVHDedicatedMachineList{}
	if err := r.reader().List(ctx, list, client.InNamespace(machine.Namespace)); err != nil {
		return err
	}
	prefix, _ := netip.ParsePrefix(machine.Spec.VRackCIDR)
	script := renderVRackScript(mac, machine.Status.VRackAddress, prefix.Bits(), public, vrackRoutes(machine, list.Items))
	revision := fmt.Sprintf("%x:%s", sha256.Sum256([]byte(script)), node.Status.NodeInfo.BootID)
	if node.Annotations[vrackConfigAnnotation] != revision || node.Labels[vrackReadyLabel] != "true" {
		fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
		key, err := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
		if err != nil {
			return err
		}
		creds, err := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name)
		if err != nil {
			return err
		}
		// Bootstrap has already established trust. A network repair must not
		// silently establish a new host identity for an existing node.
		if creds == nil || creds.HostFingerprint == "" {
			return fmt.Errorf("vRack repair requires the bootstrap host fingerprint")
		}
		if err := bootstrapOverSSH(ctx, ovhBootstrapUser, public, key, script, bootstrap.NewHostKeyState(creds.HostFingerprint)); err != nil {
			return err
		}
		before := node.DeepCopy()
		if node.Annotations == nil {
			node.Annotations = map[string]string{}
		}
		if node.Labels == nil {
			node.Labels = map[string]string{}
		}
		node.Annotations[vrackConfigAnnotation] = revision
		node.Labels[vrackReadyLabel] = "true"
		if err := r.Patch(ctx, node, client.MergeFrom(before)); err != nil {
			return err
		}
	}
	conditions.MarkTrue(machine, VRackReadyCondition)
	return nil
}

// Keep Node addresses stable: only /32 routes to participating OVH peers use
// private next hops. Cilium's VXLAN traffic then traverses vRack, while traffic
// to Hetzner, other OVH regions and the API server keeps its existing routes.
func renderVRackScript(mac, address string, bits int, public string, routes []vrackRoute) string {
	var peers strings.Builder
	for _, route := range routes {
		fmt.Fprintf(&peers, "%s %s\n", route.Public, route.Private)
	}
	return fmt.Sprintf(`#!/usr/bin/env bash
set -euo pipefail
sudo bash -s <<'TUIST_VRACK_ROOT'
set -euo pipefail
install -d -m 0755 /etc/tuist /usr/local/sbin
cat > /etc/tuist/vrack-peers <<'TUIST_VRACK_PEERS'
%[5]sTUIST_VRACK_PEERS
cat > /usr/local/sbin/tuist-vrack <<'TUIST_VRACK_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
exec 9>/run/lock/tuist-vrack.lock
flock 9
iface=
for path in /sys/class/net/*/address; do
  if [ "$(cat "$path")" = '%[1]s' ]; then
    iface=$(basename "$(dirname "$path")")
    break
  fi
done
[ -n "$iface" ] || { echo 'OVH private NIC missing' >&2; exit 1; }
# Never configure the public/default-route device as the private network.
if ip -4 route show default | grep -Eq "(^| )dev $iface( |$)"; then
  echo 'OVH private NIC is the default-route device' >&2
  exit 1
fi
ip link set dev "$iface" up
ip address replace '%[2]s/%[3]d' dev "$iface"
# Encapsulated packets retain their public Node source address. Loose reverse
# path filtering accepts them on the private NIC during asymmetric convergence.
echo 2 > "/proc/sys/net/ipv4/conf/$iface/rp_filter"
while read -r destination gateway; do
  [ -n "$destination" ] || continue
  existing=$(ip -4 route show exact "$destination/32")
  if [ -n "$existing" ] && ! grep -q ' proto 242' <<< "$existing"; then
    echo "refusing to replace an unmanaged route to $destination" >&2
    exit 1
  fi
  if ping -n -c 1 -W 2 -I '%[2]s' "$gateway" >/dev/null 2>&1; then
    ip route replace "$destination/32" via "$gateway" dev "$iface" src '%[4]s' proto 242
  else
    # A failed private link falls back to the unchanged public route.
    ip route del "$destination/32" proto 242 2>/dev/null || true
  fi
done < /etc/tuist/vrack-peers
# Remove only this service's routes when a peer leaves the fleet.
while read -r destination rest; do
  [ -n "$destination" ] || continue
  if ! grep -q "^${destination%%/32} " /etc/tuist/vrack-peers; then
    ip route del "$destination" proto 242
  fi
done < <(ip -4 route show proto 242)
TUIST_VRACK_SCRIPT
chmod 0755 /usr/local/sbin/tuist-vrack
cat > /etc/systemd/system/tuist-vrack.service <<'TUIST_VRACK_UNIT'
[Unit]
Description=OVH private cache network
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/tuist-vrack
[Install]
WantedBy=multi-user.target
TUIST_VRACK_UNIT
cat > /etc/systemd/system/tuist-vrack.timer <<'TUIST_VRACK_TIMER'
[Unit]
Description=Reconcile OVH private cache routes
[Timer]
OnBootSec=30s
OnUnitInactiveSec=30s
[Install]
WantedBy=timers.target
TUIST_VRACK_TIMER
systemctl daemon-reload
systemctl enable tuist-vrack.service tuist-vrack.timer
systemctl restart tuist-vrack.service
systemctl start tuist-vrack.timer
TUIST_VRACK_ROOT
`, mac, address, bits, public, peers.String())
}
