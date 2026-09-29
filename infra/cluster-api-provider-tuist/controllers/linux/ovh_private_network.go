package linux

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/netip"
	"sort"
	"strings"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const privateNetworkReady clusterv1.ConditionType = "PrivateNetworkReady"
const privateNetworkAnnotation = "tuist.dev/private-network"
const privateNetworkRevision = "tuist.dev/private-network-revision"
const privateNetworkMembers = "tuist.dev/private-network-members"

// Reservations outlive Machines: release starts an asynchronous OS reinstall,
// so deleting a Machine must never make its still-configured address reusable.
type privateNetworkReservations struct {
	Network   string            `json:"network"`
	CIDR      string            `json:"cidr"`
	Addresses map[string]string `json:"addresses"`
}

type privateNetworkPeer struct{ Public, Private string }

func privateNetworkCacheMachine(machine *infrav1.OVHDedicatedMachine) bool {
	return !machine.Spec.KataRuntime && privateNetworkCacheTaint(machine.Spec.NodeTaints)
}

func privateNetworkCacheTaint(taints []corev1.Taint) bool {
	for _, taint := range taints {
		if taint.Key == "tuist.dev/kura-cache" && taint.Effect == corev1.TaintEffectNoSchedule {
			return true
		}
	}
	return false
}

func privateNetworkPrefix(cidr string) (netip.Prefix, error) {
	prefix, err := netip.ParsePrefix(cidr)
	if err != nil || !prefix.Addr().Is4() || !prefix.Addr().IsPrivate() || prefix != prefix.Masked() || prefix.Bits() < 24 || prefix.Bits() > 28 {
		return netip.Prefix{}, fmt.Errorf("private network CIDR must be a canonical private IPv4 /24 through /28")
	}
	return prefix, nil
}

func allocatePrivateNetwork(network, cidr string, reservations *privateNetworkReservations, services []string) error {
	prefix, err := privateNetworkPrefix(cidr)
	if err != nil {
		return err
	}
	if !strings.HasPrefix(network, "pn-") || strings.ContainsAny(network, "/\n\r\t ") {
		return fmt.Errorf("invalid vRack ID")
	}
	if reservations.Network != "" && (reservations.Network != network || reservations.CIDR != cidr) {
		return fmt.Errorf("refusing to change an allocated private network")
	}
	reservations.Network, reservations.CIDR = network, cidr
	if reservations.Addresses == nil {
		reservations.Addresses = map[string]string{}
	}
	used := map[netip.Addr]bool{}
	for _, raw := range reservations.Addresses {
		address, err := netip.ParseAddr(raw)
		if err != nil || !prefix.Contains(address) || address.Compare(prefix.Addr().Next()) <= 0 || !prefix.Contains(address.Next()) || used[address] {
			return fmt.Errorf("invalid or duplicate private address reservation")
		}
		used[address] = true
	}
	sort.Strings(services)
	for _, service := range services {
		if reservations.Addresses[service] != "" {
			continue
		}
		address := prefix.Addr().Next().Next()
		for prefix.Contains(address.Next()) && used[address] {
			address = address.Next()
		}
		if !prefix.Contains(address.Next()) {
			return fmt.Errorf("private address pool exhausted; existing reservations must not be recycled")
		}
		reservations.Addresses[service] = address.String()
		used[address] = true
	}
	return nil
}

func (r *OVHDedicatedMachineReconciler) reservePrivateNetwork(ctx context.Context, machine *infrav1.OVHDedicatedMachine, network, cidr string) (*privateNetworkReservations, []infrav1.OVHDedicatedMachine, error) {
	r.adoptMu.Lock()
	defer r.adoptMu.Unlock()
	machines := &infrav1.OVHDedicatedMachineList{}
	if err := r.reader().List(ctx, machines, client.InNamespace(machine.Namespace)); err != nil {
		return nil, nil, err
	}
	services := []string{}
	for i := range machines.Items {
		peer := &machines.Items[i]
		if privateNetworkCacheMachine(peer) && peer.Status.ServiceName != "" {
			services = append(services, peer.Status.ServiceName)
		}
	}
	key := types.NamespacedName{Namespace: machine.Namespace, Name: r.PrivateNetworkConfigName + "-reservations"}
	cm := &corev1.ConfigMap{}
	err := r.reader().Get(ctx, key, cm)
	create := apierrors.IsNotFound(err)
	if err != nil && !create {
		return nil, nil, err
	}
	if create {
		cm = &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: key.Name, Namespace: key.Namespace}, Data: map[string]string{}}
	}
	reservations := &privateNetworkReservations{}
	if raw := cm.Data["reservations.json"]; raw != "" {
		if err := json.Unmarshal([]byte(raw), reservations); err != nil {
			return nil, nil, err
		}
	}
	if err := allocatePrivateNetwork(network, cidr, reservations, services); err != nil {
		return nil, nil, err
	}
	data, err := json.Marshal(reservations)
	if err != nil {
		return nil, nil, err
	}
	if cm.Data == nil {
		cm.Data = map[string]string{}
	}
	if cm.Data["reservations.json"] != string(data) {
		cm.Data["reservations.json"] = string(data)
		if create {
			err = r.Create(ctx, cm)
		} else {
			err = r.Update(ctx, cm)
		}
		if err != nil {
			return nil, nil, err
		}
	}
	return reservations, machines.Items, nil
}

func (r *OVHDedicatedMachineReconciler) reconcilePrivateNetwork(ctx context.Context, machine *infrav1.OVHDedicatedMachine, node *corev1.Node) (err error) {
	if r.PrivateNetworkConfigName == "" || machine.Namespace != r.PrivateNetworkNamespace || !privateNetworkCacheMachine(machine) {
		return nil
	}
	defer func() {
		if err != nil {
			conditions.MarkFalse(machine, privateNetworkReady, "ConfigurationFailed", clusterv1.ConditionSeverityError, "%s", err)
		}
	}()
	config := &corev1.ConfigMap{}
	if err = r.reader().Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: r.PrivateNetworkConfigName}, config); err != nil {
		return err
	}
	network, cidr := config.Data["vrackID"], config.Data["cidr"]
	if machine.Spec.VRackID != "" && machine.Spec.VRackID != network {
		return fmt.Errorf("machine declares a different vRack")
	}
	reservations, machines, err := r.reservePrivateNetwork(ctx, machine, network, cidr)
	if err != nil {
		return err
	}
	mac, attached, err := r.OVHClient.EnsureVRack(ctx, machine.Status.ServiceName, network)
	if err != nil {
		return err
	}
	if !attached {
		return fmt.Errorf("waiting for private NIC attachment to %s", network)
	}
	public := privateNetworkPublicAddress(machine)
	address := reservations.Addresses[machine.Status.ServiceName]
	if public == "" || address == "" {
		return fmt.Errorf("private routing requires a public identity and a reserved private address")
	}
	peers, members, owners := ovhPrivateParticipants(machine.Status.ServiceName, machines, reservations)
	membership := fmt.Sprintf("%x", sha256.Sum256([]byte(strings.Join(members, "\n"))))
	prefix, _ := netip.ParsePrefix(cidr)
	script := renderPrivateNetworkScript(mac, address, prefix.Bits(), public, peers, owners)
	revision := fmt.Sprintf("%x:%s", sha256.Sum256([]byte(script)), node.Status.NodeInfo.BootID)
	if node.Annotations[privateNetworkRevision] != revision || node.Annotations[privateNetworkMembers] != membership {
		fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
		key, err := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
		if err != nil {
			return err
		}
		creds, err := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name)
		if err != nil {
			return err
		}
		if creds == nil || creds.HostFingerprint == "" {
			return fmt.Errorf("private network repair requires the established SSH host fingerprint")
		}
		if err := bootstrapOverSSH(ctx, ovhBootstrapUser, public, key, script, bootstrap.NewHostKeyState(creds.HostFingerprint)); err != nil {
			return err
		}
		before := node.DeepCopy()
		if node.Annotations == nil {
			node.Annotations = map[string]string{}
		}
		node.Annotations[privateNetworkRevision] = revision
		node.Annotations[privateNetworkAnnotation] = network
		node.Annotations[privateNetworkMembers] = membership
		if err := r.Patch(ctx, node, client.MergeFrom(before)); err != nil {
			return err
		}
	}
	for i := range machines {
		peer := &machines[i]
		if !privateNetworkCacheMachine(peer) || !peer.DeletionTimestamp.IsZero() || privateNetworkPublicAddress(peer) == "" {
			continue
		}
		remote := &corev1.Node{}
		if err := r.reader().Get(ctx, types.NamespacedName{Name: peer.Name}, remote); err != nil {
			return err
		}
		if remote.Annotations[privateNetworkAnnotation] != network || remote.Annotations[privateNetworkMembers] != membership {
			return fmt.Errorf("waiting for private routes on %s before advertising topology", peer.Name)
		}
	}
	if node.Labels[privateNetworkAnnotation] != network {
		before := node.DeepCopy()
		if node.Labels == nil {
			node.Labels = map[string]string{}
		}
		node.Labels[privateNetworkAnnotation] = network
		if err := r.Patch(ctx, node, client.MergeFrom(before)); err != nil {
			return err
		}
	}
	conditions.MarkTrue(machine, privateNetworkReady)
	return nil
}

func privateNetworkPublicAddress(machine *infrav1.OVHDedicatedMachine) string {
	return privateNetworkExternalIPv4(machine.Status.Addresses)
}

func privateNetworkOwner(meta metav1.ObjectMeta) string {
	return meta.Name + "/" + string(meta.UID)
}

func ovhPrivateParticipants(service string, machines []infrav1.OVHDedicatedMachine, reservations *privateNetworkReservations) ([]privateNetworkPeer, []string, privateNetworkOwners) {
	peers := []privateNetworkPeer{}
	members := []string{}
	owners := privateNetworkOwners{}
	for i := range machines {
		peer := &machines[i]
		owner := privateNetworkOwner(peer.ObjectMeta)
		owners[owner] = ""
		if !privateNetworkCacheMachine(peer) {
			continue
		}
		ip := privateNetworkPublicAddress(peer)
		owners[owner] = ip
		if !peer.DeletionTimestamp.IsZero() || ip == "" {
			continue
		}
		members = append(members, peer.Name+"/"+peer.Status.ServiceName+"/"+ip+"/"+reservations.Addresses[peer.Status.ServiceName])
		if peer.Status.ServiceName != service && reservations.Addresses[peer.Status.ServiceName] != "" {
			peers = append(peers, privateNetworkPeer{Public: ip, Private: reservations.Addresses[peer.Status.ServiceName]})
		}
	}
	sort.Slice(peers, func(i, j int) bool { return peers[i].Public < peers[j].Public })
	sort.Strings(members)
	return peers, members, owners
}

func privateNetworkExternalIPv4(addresses []clusterv1.MachineAddress) string {
	for _, address := range addresses {
		if address.Type == clusterv1.MachineExternalIP {
			if ip, err := netip.ParseAddr(address.Address); err == nil && ip.Is4() {
				return ip.String()
			}
		}
	}
	return ""
}

// A less-preferred unreachable /32 survives removal of each private unicast
// route. Keep it in the main table too: Cilium's direct FIB lookups can skip
// policy-routing rules. Protocol 242 identifies the routes this service owns.
func renderPrivateNetworkScript(mac, address string, bits int, public string, peers []privateNetworkPeer, owners ...privateNetworkOwners) string {
	return renderProviderPrivateNetworkScript(mac, address, bits, public, peers, privateNetworkScriptOptions{Provider: "OVH", RootCommand: "sudo bash -s"}, owners...)
}

// Keep deleting and temporarily unaddressed Machines in this authoritative
// roster. Only completed Machine removal can retire a previously owned guard.
type privateNetworkOwners map[string]string

type privateNetworkScriptOptions struct {
	Provider        string
	RootCommand     string
	LinkPreparation string
	PingOptions     string
}

func renderProviderPrivateNetworkScript(mac, address string, bits int, public string, peers []privateNetworkPeer, options privateNetworkScriptOptions, owners ...privateNetworkOwners) string {
	var rows strings.Builder
	for _, peer := range peers {
		fmt.Fprintf(&rows, "%s %s\n", peer.Public, peer.Private)
	}
	var ownerRows strings.Builder
	if len(owners) > 0 {
		names := make([]string, 0, len(owners[0]))
		for name := range owners[0] {
			names = append(names, name)
		}
		sort.Strings(names)
		for _, name := range names {
			address := owners[0][name]
			if address == "" {
				address = "-"
			}
			fmt.Fprintf(&ownerRows, "%s %s\n", name, address)
		}
	}
	return fmt.Sprintf(`#!/usr/bin/env bash
set -euo pipefail
%[6]s <<'TUIST_PRIVATE_ROOT'
set -euo pipefail
# Prepare addresses on every host before publishing a new route membership.
# A partial initial rollout must not blackhole peers that are still public.
# Leave any previously installed guards and repair timer intact on failure.
iface=
for path in /sys/class/net/*/address; do
 if [ "$(cat "$path")" = '%[1]s' ]; then iface=$(basename "$(dirname "$path")"); break; fi
done
[ -n "$iface" ] || { echo 'private NIC missing' >&2; exit 1; }
if ip -4 route show default | grep -Eq "(^| )dev $iface( |$)"; then echo 'refusing to configure default-route interface' >&2; exit 1; fi
%[7]sip link set dev "$iface" up
ip address replace '%[2]s/%[3]d' dev "$iface"
echo 2 > "/proc/sys/net/ipv4/conf/$iface/rp_filter"
prepared=1
while read -r destination gateway; do
 [ -n "$destination" ] || continue
 if ! ping -n -c 1 -W 2 %[8]s-I '%[2]s' "$gateway" >/dev/null 2>&1; then
  echo "waiting for private address preparation on $destination" >&2
  prepared=0
 fi
done <<'TUIST_PRIVATE_PREFLIGHT'
%[5]sTUIST_PRIVATE_PREFLIGHT
[ "$prepared" -eq 1 ] || exit 1
install -d -m 0755 /etc/tuist /usr/local/sbin /etc/systemd/system/kubelet.service.d /etc/systemd/system/containerd.service.d
exec 8>/run/lock/tuist-private-network.lock
flock 8
cat > /etc/tuist/private-network-peers.new <<'TUIST_PRIVATE_PEERS'
%[5]sTUIST_PRIVATE_PEERS
mv /etc/tuist/private-network-peers.new /etc/tuist/private-network-peers
touch /etc/tuist/private-network-guard-peers
touch /etc/tuist/private-network-guard-owners
declare -A live_owners current_owners old_owners
while read -r owner destination; do
 [ -n "$owner" ] || continue
 live_owners["$owner"]=1
 if [ "$destination" != - ]; then current_owners["$destination"]="$owner"; fi
done <<'TUIST_PRIVATE_OWNERS'
%[10]sTUIST_PRIVATE_OWNERS
while read -r destination owner; do
 [ -n "$destination" ] || continue
 old_owners["$destination"]="$owner"
done < /etc/tuist/private-network-guard-owners
cp /etc/tuist/private-network-peers /etc/tuist/private-network-guard-peers.new
: > /etc/tuist/private-network-guard-owners.new
while read -r destination gateway; do
 [ -n "$destination" ] || continue
 owner=${old_owners[$destination]:-${current_owners[$destination]:-}}
 active=$(awk -v destination="$destination" '$1 == destination {print 1; exit}' /etc/tuist/private-network-peers)
 if [ -n "$active" ] && [ -n "${current_owners[$destination]:-}" ]; then owner=${current_owners[$destination]}; fi
 if [ -n "$owner" ] && [ -z "${live_owners[$owner]:-}" ]; then
  # Machine deletion has completed. Remove only routes owned by this service.
  ip -4 route del "$destination/32" metric 50 proto 242 2>/dev/null || true
  ip -4 route del unreachable "$destination/32" metric 32767 proto 242 2>/dev/null || true
  if [ -n "$(ip -4 route show exact "$destination/32" proto 242)" ]; then
   echo "owned routes to retired peer $destination remain; retaining cleanup intent" >&2
   exit 1
  fi
  continue
 fi
 printf '%%s %%s\n' "$destination" "$gateway" >> /etc/tuist/private-network-guard-peers.new
 if [ -n "$owner" ]; then printf '%%s %%s\n' "$destination" "$owner" >> /etc/tuist/private-network-guard-owners.new; fi
 # A departing host no longer gets a working route, but keeps its guard until
 # release completes. Failed or NotReady hosts remain in the owner roster.
 if [ -z "$active" ]; then
  ip -4 route del "$destination/32" metric 50 proto 242 2>/dev/null || true
 fi
done < <(cat /etc/tuist/private-network-guard-peers /etc/tuist/private-network-peers | sort -u)
sort -u -o /etc/tuist/private-network-guard-peers.new /etc/tuist/private-network-guard-peers.new
mv /etc/tuist/private-network-guard-peers.new /etc/tuist/private-network-guard-peers
mv /etc/tuist/private-network-guard-owners.new /etc/tuist/private-network-guard-owners
cat > /usr/local/sbin/tuist-private-network.new <<'TUIST_PRIVATE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
exec 9>/run/lock/tuist-private-network.lock
flock 9
while read -r destination gateway; do
 [ -n "$destination" ] || continue
 unmanaged=$(ip -4 route show exact "$destination/32" | grep -v ' proto 242' || true)
 if [ -n "$unmanaged" ]; then
  echo "refusing to replace unmanaged route to $destination" >&2
  exit 1
 fi
 ip -4 route replace unreachable "$destination/32" metric 32767 proto 242
done < /etc/tuist/private-network-guard-peers
if [ "${1:-}" = --guard-only ]; then exit 0; fi
iface=
for path in /sys/class/net/*/address; do
 if [ "$(cat "$path")" = '%[1]s' ]; then iface=$(basename "$(dirname "$path")"); break; fi
done
[ -n "$iface" ] || { echo 'private NIC missing' >&2; exit 1; }
if ip -4 route show default | grep -Eq "(^| )dev $iface( |$)"; then echo 'refusing to configure default-route interface' >&2; exit 1; fi
%[7]sip link set dev "$iface" up
ip address replace '%[2]s/%[3]d' dev "$iface"
echo 2 > "/proc/sys/net/ipv4/conf/$iface/rp_filter"
failed=0
while read -r destination gateway; do
 [ -n "$destination" ] || continue
 if ping -n -c 1 -W 2 %[8]s-I '%[2]s' "$gateway" >/dev/null 2>&1; then
  ip -4 route replace "$destination/32" via "$gateway" dev "$iface" onlink src '%[4]s' metric 50 proto 242
 else
  ip -4 route del "$destination/32" metric 50 proto 242 2>/dev/null || true
  failed=1
 fi
done < /etc/tuist/private-network-peers
# The controller retires guards only after their owning Machine disappears.
exit "$failed"
TUIST_PRIVATE_SCRIPT
chmod 0755 /usr/local/sbin/tuist-private-network.new
mv /usr/local/sbin/tuist-private-network.new /usr/local/sbin/tuist-private-network
cat > /etc/systemd/system/tuist-private-network-guard.service <<'TUIST_PRIVATE_GUARD'
[Unit]
Description=Block public fallback before starting Kubernetes
Before=kubelet.service containerd.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/tuist-private-network --guard-only
TUIST_PRIVATE_GUARD
cat > /etc/systemd/system/kubelet.service.d/30-private-network.conf <<'TUIST_PRIVATE_KUBELET'
[Unit]
Requires=tuist-private-network-guard.service
After=tuist-private-network-guard.service
TUIST_PRIVATE_KUBELET
cp /etc/systemd/system/kubelet.service.d/30-private-network.conf /etc/systemd/system/containerd.service.d/30-private-network.conf
cat > /etc/systemd/system/tuist-private-network.service <<'TUIST_PRIVATE_UNIT'
[Unit]
Description=Private-only %[9]s peer routes
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/tuist-private-network
[Install]
WantedBy=multi-user.target
TUIST_PRIVATE_UNIT
cat > /etc/systemd/system/tuist-private-network.timer <<'TUIST_PRIVATE_TIMER'
[Unit]
Description=Repair private-only %[9]s peer routes
[Timer]
OnBootSec=5s
OnUnitInactiveSec=15s
[Install]
WantedBy=timers.target
TUIST_PRIVATE_TIMER
flock -u 8
systemctl daemon-reload
systemctl enable tuist-private-network.service tuist-private-network.timer
systemctl start tuist-private-network-guard.service
systemctl start tuist-private-network.timer
systemctl restart tuist-private-network.service
TUIST_PRIVATE_ROOT
`, mac, address, bits, public, rows.String(), options.RootCommand, options.LinkPreparation, options.PingOptions, options.Provider, ownerRows.String())
}
