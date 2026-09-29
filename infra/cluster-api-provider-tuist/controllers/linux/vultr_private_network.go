package linux

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net"
	"net/netip"
	"sort"
	"strings"
	"time"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/vultr"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

type vultrPrivateRegion struct {
	Description string `json:"description"`
	CIDR        string `json:"cidr"`
	Qualified   bool   `json:"qualified"`
}

type vultrNetworkState struct {
	Desired            vultrPrivateRegion `json:"desired"`
	ID                 string             `json:"id,omitempty"`
	CreateRequested    bool               `json:"createRequested,omitempty"`
	AttachmentRequests map[string]string  `json:"attachmentRequests,omitempty"`
}

const vultrPrivateInventoryTTL = time.Minute

type vultrPrivateVPCCacheEntry struct {
	desired vultrPrivateRegion
	network vultr.VPC
	expires time.Time
}

type vultrPrivateNICCacheEntry struct {
	interfaces []vultr.VPCInterface
	expires    time.Time
}

// The retained state survives Machines and Helm changes. Record intent before
// the non-idempotent provider POST; an uncertain create must never be retried
// blindly, even after a controller restart or a stale provider list.
func (r *VultrMachineReconciler) ensurePrivateVPC(ctx context.Context, region string, desired vultrPrivateRegion) (*vultr.VPC, error) {
	r.privateNetworkMu.Lock()
	defer r.privateNetworkMu.Unlock()
	if cached, ok := r.privateVPCCache[region]; ok && cached.desired == desired && time.Now().Before(cached.expires) {
		network := cached.network
		return &network, nil
	}
	prefix, err := privateNetworkPrefix(desired.CIDR)
	if err != nil {
		return nil, err
	}
	network, err := r.VultrClient.EnsureVPC(ctx, vultr.VPC{Region: region, Description: desired.Description, Subnet: prefix.Addr().String(), Mask: prefix.Bits()}, false)
	if err != nil {
		return nil, err
	}
	key := types.NamespacedName{Namespace: r.PrivateNetworkNamespace, Name: r.PrivateNetworkConfigName + "-state"}
	cm := &corev1.ConfigMap{}
	err = r.reader().Get(ctx, key, cm)
	if apierrors.IsNotFound(err) {
		cm = &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: key.Name, Namespace: key.Namespace}, Data: map[string]string{}}
		if err = r.Create(ctx, cm); err != nil {
			return nil, err
		}
	} else if err != nil {
		return nil, err
	}
	state := vultrNetworkState{}
	if raw := cm.Data[region]; raw != "" {
		if err = json.Unmarshal([]byte(raw), &state); err != nil {
			return nil, err
		}
		if state.Desired.Description != desired.Description || state.Desired.CIDR != desired.CIDR {
			return nil, fmt.Errorf("refusing to change a retained Vultr VPC definition")
		}
	}
	if state.ID != "" && state.ID != network.ID {
		return nil, fmt.Errorf("retained Vultr VPC disappeared or changed identity; explicit recovery required")
	}
	save := func() error {
		state.Desired = desired
		data, e := json.Marshal(state)
		if e != nil {
			return e
		}
		if cm.Data == nil {
			cm.Data = map[string]string{}
		}
		if cm.Data[region] == string(data) {
			return nil
		}
		cm.Data[region] = string(data)
		return r.Update(ctx, cm)
	}
	if network.ID == "" {
		if state.CreateRequested {
			return nil, fmt.Errorf("Vultr VPC create outcome is uncertain; inspect provider state before clearing retained intent")
		}
		state.CreateRequested = true
		if err = save(); err != nil {
			return nil, err
		}
		network, err = r.VultrClient.EnsureVPC(ctx, *network, true)
		if err != nil {
			return nil, err
		}
	}
	state.ID = network.ID
	if err = save(); err != nil {
		return nil, err
	}
	if r.privateVPCCache == nil {
		r.privateVPCCache = map[string]vultrPrivateVPCCacheEntry{}
	}
	for key, cached := range r.privateVPCCache {
		if time.Now().After(cached.expires) {
			delete(r.privateVPCCache, key)
		}
	}
	r.privateVPCCache[region] = vultrPrivateVPCCacheEntry{desired: desired, network: *network, expires: time.Now().Add(vultrPrivateInventoryTTL)}
	return network, nil
}

// Serialize cache misses so a fleet reconcile does one provider read per host
// per minute, not one read per host pair. Errors are never cached.
func (r *VultrMachineReconciler) privateInterfaces(ctx context.Context, id string) ([]vultr.VPCInterface, error) {
	r.privateNetworkMu.Lock()
	defer r.privateNetworkMu.Unlock()
	if cached, ok := r.privateNICCache[id]; ok && time.Now().Before(cached.expires) {
		return append([]vultr.VPCInterface(nil), cached.interfaces...), nil
	}
	interfaces, err := r.VultrClient.BareMetalVPCs(ctx, id)
	if err != nil {
		return nil, err
	}
	if r.privateNICCache == nil {
		r.privateNICCache = map[string]vultrPrivateNICCacheEntry{}
	}
	for key, cached := range r.privateNICCache {
		if time.Now().After(cached.expires) {
			delete(r.privateNICCache, key)
		}
	}
	r.privateNICCache[id] = vultrPrivateNICCacheEntry{interfaces: append([]vultr.VPCInterface(nil), interfaces...), expires: time.Now().Add(vultrPrivateInventoryTTL)}
	return interfaces, nil
}

func (r *VultrMachineReconciler) requestPrivateAttachment(ctx context.Context, region, instance, network string) error {
	r.privateNetworkMu.Lock()
	defer r.privateNetworkMu.Unlock()
	cm := &corev1.ConfigMap{}
	if err := r.reader().Get(ctx, types.NamespacedName{Namespace: r.PrivateNetworkNamespace, Name: r.PrivateNetworkConfigName + "-state"}, cm); err != nil {
		return err
	}
	var state vultrNetworkState
	if err := json.Unmarshal([]byte(cm.Data[region]), &state); err != nil {
		return err
	}
	if state.ID != network {
		return fmt.Errorf("retained VPC identity changed before attachment")
	}
	if retained := state.AttachmentRequests[instance]; retained != "" {
		return fmt.Errorf("Vultr VPC attachment is pending or uncertain; inspect provider state before clearing retained intent")
	}
	if state.AttachmentRequests == nil {
		state.AttachmentRequests = map[string]string{}
	}
	state.AttachmentRequests[instance] = network
	data, err := json.Marshal(state)
	if err != nil {
		return err
	}
	cm.Data[region] = string(data)
	if err := r.Update(ctx, cm); err != nil {
		return err
	}
	delete(r.privateNICCache, instance)
	return r.VultrClient.AttachBareMetalVPC(ctx, instance, network)
}

func vultrPrivateCacheMachine(machine *infrav1.VultrMachine) bool {
	return privateNetworkCacheTaint(machine.Spec.NodeTaints)
}

func vultrPrivatePublicAddress(machine *infrav1.VultrMachine) string {
	return privateNetworkExternalIPv4(machine.Status.Addresses)
}

func validateVultrInterface(interfaces []vultr.VPCInterface, network *vultr.VPC) (*vultr.VPCInterface, error) {
	if len(interfaces) == 0 {
		return nil, nil
	}
	if len(interfaces) != 1 || interfaces[0].ID != network.ID {
		return nil, fmt.Errorf("refusing to replace an existing Vultr VPC attachment")
	}
	nic := interfaces[0]
	mac, err := net.ParseMAC(nic.MAC)
	if err != nil || len(mac) != 6 || mac[0]&1 != 0 || nic.MAC != strings.ToLower(mac.String()) || mac.String() == "00:00:00:00:00:00" {
		return nil, fmt.Errorf("invalid provider-assigned private MAC")
	}
	ip, err := netip.ParseAddr(nic.Address)
	prefix, e := netip.ParsePrefix(fmt.Sprintf("%s/%d", network.Subnet, network.Mask))
	if err != nil || e != nil || !ip.Is4() || !prefix.Contains(ip) || ip.Compare(prefix.Addr().Next()) <= 0 || !prefix.Contains(ip.Next()) {
		return nil, fmt.Errorf("invalid provider-assigned private address")
	}
	return &nic, nil
}

func (r *VultrMachineReconciler) reconcilePrivateNetwork(ctx context.Context, machine *infrav1.VultrMachine, node *corev1.Node) (err error) {
	if r.PrivateNetworkConfigName == "" || machine.Namespace != r.PrivateNetworkNamespace || !vultrPrivateCacheMachine(machine) {
		return nil
	}
	defer func() {
		if err != nil {
			conditions.MarkFalse(machine, privateNetworkReady, "ConfigurationFailed", clusterv1.ConditionSeverityError, "%s", err)
		}
	}()
	config := &corev1.ConfigMap{}
	if err = r.reader().Get(ctx, types.NamespacedName{Namespace: r.PrivateNetworkNamespace, Name: r.PrivateNetworkConfigName}, config); err != nil {
		return err
	}
	var regions map[string]vultrPrivateRegion
	if err = json.Unmarshal([]byte(config.Data["regions.json"]), &regions); err != nil {
		return err
	}
	qualified := 0
	for _, region := range regions {
		if region.Qualified {
			qualified++
		}
	}
	if qualified > 1 {
		return fmt.Errorf("multiple qualified Vultr regions require an explicit cross-domain runtime policy")
	}
	region := firstNonEmpty(machine.Spec.Region, r.DefaultRegion)
	desired, exists := regions[region]
	if !exists {
		return fmt.Errorf("Vultr private configuration omits machine region %s", region)
	}
	network, err := r.ensurePrivateVPC(ctx, region, desired)
	if err != nil {
		return err
	}
	if !desired.Qualified {
		if node.Annotations[privateNetworkAnnotation] != "" {
			return fmt.Errorf("private routes already installed; explicit rollback required before withdrawing qualification")
		}
		conditions.MarkFalse(machine, privateNetworkReady, "QualificationPending", clusterv1.ConditionSeverityInfo, "VPC is managed; host transport is not qualified")
		return nil
	}
	interfaces, err := r.privateInterfaces(ctx, machine.Status.InstanceID)
	if err != nil {
		return err
	}
	nic, err := validateVultrInterface(interfaces, network)
	if err != nil {
		return err
	}
	if nic == nil {
		if err = r.requestPrivateAttachment(ctx, region, machine.Status.InstanceID, network.ID); err != nil {
			return err
		}
		return fmt.Errorf("waiting for provider-assigned private NIC after attachment")
	}
	machines := &infrav1.VultrMachineList{}
	if err = r.reader().List(ctx, machines, client.InNamespace(machine.Namespace)); err != nil {
		return err
	}
	peers := []privateNetworkPeer{}
	members := []string{}
	names := []string{}
	used := map[string]bool{}
	owners := privateNetworkOwners{}
	for i := range machines.Items {
		peer := &machines.Items[i]
		owner := privateNetworkOwner(peer.ObjectMeta)
		owners[owner] = ""
		if vultrPrivateCacheMachine(peer) {
			owners[owner] = vultrPrivatePublicAddress(peer)
		}
		if !vultrPrivateCacheMachine(peer) || !peer.DeletionTimestamp.IsZero() || firstNonEmpty(peer.Spec.Region, r.DefaultRegion) != region || peer.Status.InstanceID == "" {
			continue
		}
		public := vultrPrivatePublicAddress(peer)
		if public == "" {
			continue
		}
		attachments, e := r.privateInterfaces(ctx, peer.Status.InstanceID)
		if e != nil {
			return e
		}
		assignment, e := validateVultrInterface(attachments, network)
		if e != nil {
			return e
		}
		if assignment == nil {
			return fmt.Errorf("waiting for peer VPC attachment on %s", peer.Name)
		}
		if used[assignment.Address] {
			return fmt.Errorf("duplicate provider-assigned private address")
		}
		used[assignment.Address] = true
		members = append(members, peer.Name+"/"+peer.Status.InstanceID+"/"+public+"/"+assignment.Address)
		names = append(names, peer.Name)
		if peer.Name != machine.Name {
			peers = append(peers, privateNetworkPeer{Public: public, Private: assignment.Address})
		}
	}
	public := vultrPrivatePublicAddress(machine)
	if public == "" || node.Status.NodeInfo.BootID == "" {
		return fmt.Errorf("private routing requires a public node identity and boot ID")
	}
	sort.Strings(members)
	sort.Slice(peers, func(i, j int) bool { return peers[i].Public < peers[j].Public })
	membership := fmt.Sprintf("%x", sha256.Sum256([]byte(strings.Join(members, "\n"))))
	script := renderVultrPrivateNetworkScript(nic.MAC, nic.Address, network.Mask, public, peers, owners)
	revision := fmt.Sprintf("%x:%s", sha256.Sum256([]byte(script)), node.Status.NodeInfo.BootID)
	if node.Annotations[privateNetworkRevision] != revision || node.Annotations[privateNetworkMembers] != membership {
		fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
		key, e := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
		if e != nil {
			return e
		}
		creds, e := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name)
		if e != nil {
			return e
		}
		if creds == nil || creds.HostFingerprint == "" {
			return fmt.Errorf("private route repair requires the established host fingerprint")
		}
		if _, e = r.runner()(ctx, vultrBootstrapUser, public, key, script, bootstrap.NewHostKeyState(creds.HostFingerprint)); e != nil {
			return e
		}
		before := node.DeepCopy()
		if node.Annotations == nil {
			node.Annotations = map[string]string{}
		}
		node.Annotations[privateNetworkRevision] = revision
		node.Annotations[privateNetworkAnnotation] = network.ID
		node.Annotations[privateNetworkMembers] = membership
		if err = r.Patch(ctx, node, client.MergeFrom(before)); err != nil {
			return err
		}
	}
	for _, name := range names {
		remote := &corev1.Node{}
		if err = r.reader().Get(ctx, types.NamespacedName{Name: name}, remote); err != nil {
			return err
		}
		if remote.Status.NodeInfo.BootID == "" || remote.Annotations[privateNetworkAnnotation] != network.ID || remote.Annotations[privateNetworkMembers] != membership || !strings.HasSuffix(remote.Annotations[privateNetworkRevision], ":"+remote.Status.NodeInfo.BootID) {
			return fmt.Errorf("waiting for converged private routes on %s", name)
		}
	}
	if node.Labels[privateNetworkAnnotation] != network.ID {
		before := node.DeepCopy()
		if node.Labels == nil {
			node.Labels = map[string]string{}
		}
		node.Labels[privateNetworkAnnotation] = network.ID
		if err = r.Patch(ctx, node, client.MergeFrom(before)); err != nil {
			return err
		}
	}
	conditions.MarkTrue(machine, privateNetworkReady)
	return nil
}

// Restore the qualified encapsulation MTU even if Cloud-Init later renders a
// smaller provider default. Never attest a path from a small ping alone.
func renderVultrPrivateNetworkScript(mac, address string, bits int, public string, peers []privateNetworkPeer, owners ...privateNetworkOwners) string {
	return renderProviderPrivateNetworkScript(mac, address, bits, public, peers, privateNetworkScriptOptions{
		Provider: "Vultr", RootCommand: "bash -s",
		LinkPreparation: "ip link set dev \"$iface\" mtu 1500\n",
		PingOptions:     "-M do -s 1472 ",
	}, owners...)
}
