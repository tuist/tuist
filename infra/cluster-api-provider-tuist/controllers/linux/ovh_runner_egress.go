package linux

import (
	"context"
	"crypto/sha256"
	_ "embed"
	"encoding/json"
	"fmt"
	"net/netip"
	"reflect"
	"regexp"
	"strings"

	"github.com/prometheus/client_golang/prometheus"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const runnerEgressReady clusterv1.ConditionType = "RunnerEgressReady"
const runnerEgressRevision = "tuist.dev/runner-egress-revision"
const runnerEgressAddress = "tuist.dev/runner-egress-ip"
const runnerEgressOwner = "tuist.dev/runner-egress-owner"

//go:embed ovh_runner_egress.sh
var runnerEgressScript string

var runnerVRackID = regexp.MustCompile(`^pn-[0-9]+$`)

var runnerEgressInfo = prometheus.NewGaugeVec(prometheus.GaugeOpts{
	Name: "capt_runner_egress_info",
	Help: "Configured OVH runner egress NIC and block, for joining node network counters.",
}, []string{"node", "mac", "vrack", "cidr"})

func init() { metrics.Registry.MustRegister(runnerEgressInfo) }

type runnerEgressReservation struct {
	Service string `json:"service"`
	Address string `json:"address"`
	MAC     string `json:"mac,omitempty"`
}

type runnerEgressReservations struct {
	Network  string                             `json:"network"`
	CIDR     string                             `json:"cidr"`
	Machines map[string]runnerEgressReservation `json:"machines"`
}

func runnerEgressPrefix(network, cidr string) (netip.Prefix, netip.Addr, error) {
	prefix, err := netip.ParsePrefix(cidr)
	if err != nil || !prefix.Addr().Is4() || prefix != prefix.Masked() || prefix.Bits() < 24 || prefix.Bits() > 29 || !prefix.Addr().IsGlobalUnicast() || prefix.Addr().IsPrivate() || netip.MustParsePrefix("100.64.0.0/10").Contains(prefix.Addr()) || !runnerVRackID.MatchString(network) {
		return netip.Prefix{}, netip.Addr{}, fmt.Errorf("runner egress requires a vRack ID and a canonical public IPv4 /24 through /29")
	}
	gateway := prefix.Addr()
	for i := 0; i < (1<<(32-prefix.Bits()))-2; i++ {
		gateway = gateway.Next()
	}
	return prefix, gateway, nil
}

func allocateRunnerEgress(state *runnerEgressReservations, network, cidr, owner, service string) (runnerEgressReservation, error) {
	prefix, gateway, err := runnerEgressPrefix(network, cidr)
	if err != nil {
		return runnerEgressReservation{}, err
	}
	if owner == "" || service == "" {
		return runnerEgressReservation{}, fmt.Errorf("runner egress reservation requires machine UID and service")
	}
	if len(state.Machines) > 0 && (state.Network != network || state.CIDR != cidr) {
		return runnerEgressReservation{}, fmt.Errorf("disable and clean up runner egress before changing the allocated block or vRack")
	}
	used := map[netip.Addr]bool{}
	for key, reservation := range state.Machines {
		address, err := netip.ParseAddr(reservation.Address)
		if err != nil || !prefix.Contains(address) || address.Compare(prefix.Addr()) <= 0 || address.Compare(gateway) >= 0 || used[address] || reservation.Service == "" {
			return runnerEgressReservation{}, fmt.Errorf("invalid or duplicate runner egress reservation")
		}
		if key != owner && reservation.Service == service {
			return runnerEgressReservation{}, fmt.Errorf("service is still reserved by another Machine")
		}
		used[address] = true
	}
	if existing, ok := state.Machines[owner]; ok {
		if existing.Service != service {
			return runnerEgressReservation{}, fmt.Errorf("refusing to move a reserved address to another service")
		}
		return existing, nil
	}
	address := prefix.Addr().Next()
	for used[address] {
		address = address.Next()
	}
	if address.Compare(gateway) >= 0 {
		return runnerEgressReservation{}, fmt.Errorf("runner egress block exhausted; retained reservations require confirmed host cleanup")
	}
	if state.Machines == nil {
		state.Machines = map[string]runnerEgressReservation{}
	}
	state.Network, state.CIDR = network, cidr
	reservation := runnerEgressReservation{Service: service, Address: address.String()}
	state.Machines[owner] = reservation
	return reservation, nil
}

func (r *OVHDedicatedMachineReconciler) runnerEgressState(ctx context.Context, namespace string) (*corev1.ConfigMap, *runnerEgressReservations, error) {
	cm := &corev1.ConfigMap{}
	key := types.NamespacedName{Namespace: namespace, Name: r.RunnerEgressConfigName + "-reservations"}
	err := r.reader().Get(ctx, key, cm)
	if apierrors.IsNotFound(err) {
		cm = &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: key.Name, Namespace: key.Namespace}}
	} else if err != nil {
		return nil, nil, err
	}
	state := &runnerEgressReservations{}
	if raw := cm.Data["reservations.json"]; raw != "" {
		if err := json.Unmarshal([]byte(raw), state); err != nil {
			return nil, nil, err
		}
	}
	return cm, state, nil
}

func (r *OVHDedicatedMachineReconciler) saveRunnerEgressState(ctx context.Context, cm *corev1.ConfigMap, state *runnerEgressReservations) error {
	data, err := json.Marshal(state)
	if err != nil {
		return err
	}
	if cm.Data["reservations.json"] == string(data) {
		return nil
	}
	if cm.Data == nil {
		cm.Data = map[string]string{}
	}
	cm.Data["reservations.json"] = string(data)
	if cm.ResourceVersion == "" {
		return r.Create(ctx, cm)
	}
	return r.Update(ctx, cm)
}

func (r *OVHDedicatedMachineReconciler) reserveRunnerEgress(ctx context.Context, machine *infrav1.OVHDedicatedMachine, network, cidr string) (runnerEgressReservation, error) {
	r.runnerEgressMu.Lock()
	defer r.runnerEgressMu.Unlock()
	cm, state, err := r.runnerEgressState(ctx, machine.Namespace)
	if err != nil {
		return runnerEgressReservation{}, err
	}
	reservation, err := allocateRunnerEgress(state, network, cidr, string(machine.UID), machine.Status.ServiceName)
	if err != nil {
		return runnerEgressReservation{}, err
	}
	return reservation, r.saveRunnerEgressState(ctx, cm, state)
}

func (r *OVHDedicatedMachineReconciler) runRunnerEgressScript(ctx context.Context, machine *infrav1.OVHDedicatedMachine, script string) error {
	if r.RunnerEgressRunScript != nil {
		return r.RunnerEgressRunScript(ctx, machine, script)
	}
	ctx, cancel := context.WithTimeout(ctx, ovhSSHTimeout)
	defer cancel()
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
		return fmt.Errorf("runner egress repair requires the established SSH host fingerprint")
	}
	public := privateNetworkPublicAddress(machine)
	if public == "" {
		return fmt.Errorf("runner egress repair requires the primary public IPv4 address")
	}
	return bootstrapOverSSH(ctx, ovhBootstrapUser, public, key, script, bootstrap.NewHostKeyState(creds.HostFingerprint))
}

func renderRunnerEgressScript(reservation runnerEgressReservation, network, cidr string, remove bool) (string, error) {
	prefix, gateway, err := runnerEgressPrefix(network, cidr)
	if err != nil {
		return "", err
	}
	address, err := netip.ParseAddr(reservation.Address)
	if err != nil || !prefix.Contains(address) || address.Compare(prefix.Addr()) <= 0 || address.Compare(gateway) >= 0 || !regexp.MustCompile(`^([0-9a-f]{2}:){5}[0-9a-f]{2}$`).MatchString(reservation.MAC) {
		return "", fmt.Errorf("invalid runner egress host configuration")
	}
	mode := "apply"
	if remove {
		mode = "remove"
	}
	return strings.NewReplacer("@MAC@", reservation.MAC, "@ADDRESS@", reservation.Address, "@GATEWAY@", gateway.String(), "@MODE@", mode).Replace(runnerEgressScript), nil
}

func (r *OVHDedicatedMachineReconciler) reconcileRunnerEgress(ctx context.Context, machine *infrav1.OVHDedicatedMachine, node *corev1.Node) (err error) {
	if r.RunnerEgressConfigName == "" || machine.Namespace != r.RunnerEgressNamespace {
		return nil
	}
	defer func() {
		if err != nil {
			conditions.MarkFalse(machine, runnerEgressReady, "ConfigurationFailed", clusterv1.ConditionSeverityError, "%s", err)
		}
	}()
	config := &corev1.ConfigMap{}
	if err := r.reader().Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: r.RunnerEgressConfigName}, config); err != nil {
		return err
	}
	if !machine.Spec.KataRuntime || config.Data["enabled"] == "false" {
		if err := r.cleanupRunnerEgress(ctx, machine); err != nil {
			return err
		}
		conditions.Delete(machine, runnerEgressReady)
		return nil
	}
	if config.Data["enabled"] != "true" {
		return fmt.Errorf("runner egress config requires enabled=true or enabled=false")
	}
	network, cidr := config.Data["vrackID"], config.Data["cidr"]
	if machine.Spec.VRackID != "" && machine.Spec.VRackID != network {
		return fmt.Errorf("machine declares a different vRack")
	}
	if existing := node.Annotations[privateNetworkAnnotation]; existing != "" && existing != network {
		return fmt.Errorf("runner already uses private network %s; retire or preserve it before enabling egress on %s", existing, network)
	}
	if node.Labels[corev1.LabelHostname] != node.Name || node.Name != machine.Name || node.Status.NodeInfo.BootID == "" {
		return fmt.Errorf("runner egress requires the machine's hostname-labelled Node and boot ID")
	}
	reservation, err := r.reserveRunnerEgress(ctx, machine, network, cidr)
	if err != nil {
		return err
	}
	mac, attached, err := r.OVHClient.EnsureVRack(ctx, reservation.Service, network)
	if err != nil {
		return err
	}
	if !attached {
		return fmt.Errorf("waiting for runner vRack NIC attachment")
	}
	// Persist cleanup intent before SSH, including when its result is uncertain.
	r.runnerEgressMu.Lock()
	cm, state, err := r.runnerEgressState(ctx, machine.Namespace)
	if err == nil {
		current, ok := state.Machines[string(machine.UID)]
		if !ok || current.Address != reservation.Address || (current.MAC != "" && current.MAC != mac) {
			err = fmt.Errorf("runner egress reservation changed during attachment")
		} else {
			reservation.MAC = mac
			state.Machines[string(machine.UID)] = reservation
			err = r.saveRunnerEgressState(ctx, cm, state)
		}
	}
	r.runnerEgressMu.Unlock()
	if err != nil {
		return err
	}
	script, err := renderRunnerEgressScript(reservation, network, cidr, false)
	if err != nil {
		return err
	}
	revision := fmt.Sprintf("%x:%s", sha256.Sum256([]byte(script)), node.Status.NodeInfo.BootID)
	if node.Annotations[runnerEgressRevision] != revision {
		if err := r.runRunnerEgressScript(ctx, machine, script); err != nil {
			return err
		}
	}
	// A changed revision updates the policy too, forcing Cilium to reselect the
	// device after reboot even when its desired egress IP has not changed.
	if err := r.ensureRunnerEgressPolicy(ctx, machine, node, reservation.Address, revision); err != nil {
		return err
	}
	before := node.DeepCopy()
	if node.Annotations == nil {
		node.Annotations = map[string]string{}
	}
	node.Annotations[runnerEgressRevision], node.Annotations[runnerEgressAddress] = revision, reservation.Address
	if !reflect.DeepEqual(before.Annotations, node.Annotations) {
		if err := r.Patch(ctx, node, client.MergeFrom(before)); err != nil {
			return err
		}
	}
	conditions.MarkTrue(machine, runnerEgressReady)
	runnerEgressInfo.DeletePartialMatch(prometheus.Labels{"node": node.Name})
	runnerEgressInfo.WithLabelValues(node.Name, reservation.MAC, network, cidr).Set(1)
	return nil
}

func runnerEgressPolicy(machine *infrav1.OVHDedicatedMachine) *unstructured.Unstructured {
	policy := &unstructured.Unstructured{}
	policy.SetAPIVersion("cilium.io/v2")
	policy.SetKind("CiliumEgressGatewayPolicy")
	policy.SetName("ovh-runner-" + string(machine.UID))
	return policy
}

func (r *OVHDedicatedMachineReconciler) ensureRunnerEgressPolicy(ctx context.Context, machine *infrav1.OVHDedicatedMachine, node *corev1.Node, address, revision string) error {
	desired := runnerEgressPolicy(machine)
	desired.SetAnnotations(map[string]string{runnerEgressOwner: machine.Namespace + "/" + machine.Name + "/" + string(machine.UID), runnerEgressRevision: revision})
	selector := map[string]any{"matchLabels": map[string]any{corev1.LabelHostname: node.Name}}
	desired.Object["spec"] = map[string]any{
		"selectors":        []any{map[string]any{"podSelector": map[string]any{"matchLabels": map[string]any{"tuist.dev/runner": "true", "io.kubernetes.pod.namespace": "tuist-runners"}}, "nodeSelector": selector}},
		"destinationCIDRs": []any{"0.0.0.0/0"},
		"excludedCIDRs":    []any{"10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "169.254.0.0/16"},
		"egressGateway":    map[string]any{"nodeSelector": selector, "egressIP": address},
	}
	current := runnerEgressPolicy(machine)
	err := r.reader().Get(ctx, client.ObjectKeyFromObject(current), current)
	if apierrors.IsNotFound(err) {
		return r.Create(ctx, desired)
	}
	if err != nil {
		return err
	}
	if current.GetAnnotations()[runnerEgressOwner] != desired.GetAnnotations()[runnerEgressOwner] {
		return fmt.Errorf("refusing to replace an unowned runner egress policy")
	}
	if !current.GetDeletionTimestamp().IsZero() {
		return fmt.Errorf("waiting for runner egress policy deletion")
	}
	if reflect.DeepEqual(current.Object["spec"], desired.Object["spec"]) && current.GetAnnotations()[runnerEgressRevision] == revision {
		return nil
	}
	before := current.DeepCopy()
	current.Object["spec"] = desired.Object["spec"]
	annotations := current.GetAnnotations()
	annotations[runnerEgressRevision] = revision
	current.SetAnnotations(annotations)
	return r.Patch(ctx, current, client.MergeFrom(before))
}

func (r *OVHDedicatedMachineReconciler) cleanupRunnerEgress(ctx context.Context, machine *infrav1.OVHDedicatedMachine) error {
	if r.RunnerEgressConfigName == "" || machine.Namespace != r.RunnerEgressNamespace {
		return nil
	}
	// Serialize allocation with release. The uncached reader and ConfigMap resource
	// version also protect against stale state and a leader handover.
	r.runnerEgressMu.Lock()
	defer r.runnerEgressMu.Unlock()
	cm, state, err := r.runnerEgressState(ctx, machine.Namespace)
	if err != nil {
		return err
	}
	reservation, ok := state.Machines[string(machine.UID)]
	if !ok {
		runnerEgressInfo.DeletePartialMatch(prometheus.Labels{"node": machine.Name})
		return nil
	}
	policy := runnerEgressPolicy(machine)
	err = r.reader().Get(ctx, client.ObjectKeyFromObject(policy), policy)
	if err == nil {
		if policy.GetAnnotations()[runnerEgressOwner] != machine.Namespace+"/"+machine.Name+"/"+string(machine.UID) {
			return fmt.Errorf("refusing to delete an unowned runner egress policy")
		}
		if err := r.Delete(ctx, policy, client.Preconditions{UID: ptrUID(policy.GetUID())}); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
		return fmt.Errorf("waiting for runner egress policy withdrawal before releasing its address")
	}
	if !apierrors.IsNotFound(err) {
		return err
	}
	if reservation.Service != machine.Status.ServiceName {
		return fmt.Errorf("runner egress cleanup service differs from its reservation")
	}
	if reservation.MAC != "" {
		script, err := renderRunnerEgressScript(reservation, state.Network, state.CIDR, true)
		if err != nil {
			return err
		}
		if err := r.runRunnerEgressScript(ctx, machine, script); err != nil {
			return err
		}
	}
	node := &corev1.Node{}
	if err := r.reader().Get(ctx, types.NamespacedName{Name: machine.Name}, node); err == nil {
		before := node.DeepCopy()
		delete(node.Annotations, runnerEgressRevision)
		delete(node.Annotations, runnerEgressAddress)
		if err := r.Patch(ctx, node, client.MergeFrom(before)); err != nil {
			return err
		}
	} else if !apierrors.IsNotFound(err) {
		return err
	}
	delete(state.Machines, string(machine.UID))
	if err := r.saveRunnerEgressState(ctx, cm, state); err != nil {
		return err
	}
	runnerEgressInfo.DeletePartialMatch(prometheus.Labels{"node": machine.Name})
	return nil
}

func ptrUID(uid types.UID) *types.UID { return &uid }
