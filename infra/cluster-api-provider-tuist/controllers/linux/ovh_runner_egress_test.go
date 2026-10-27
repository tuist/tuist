package linux

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/client/interceptor"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

func TestRunnerEgressAllocation(t *testing.T) {
	for _, bits := range []int{29, 27} {
		t.Run(fmt.Sprint(bits), func(t *testing.T) {
			state := &runnerEgressReservations{}
			cidr := fmt.Sprintf("198.51.100.0/%d", bits)
			usable := (1 << (32 - bits)) - 3
			for i := 1; i <= usable; i++ {
				owner := fmt.Sprint(i)
				got, err := allocateRunnerEgress(state, "pn-123", cidr, owner, "server-"+owner)
				if err != nil || got.Address != fmt.Sprintf("198.51.100.%d", i) {
					t.Fatalf("allocation %d: %+v %v", i, got, err)
				}
				again, err := allocateRunnerEgress(state, "pn-123", cidr, owner, "server-"+owner)
				if err != nil || again != got {
					t.Fatal("unstable allocation", again, err)
				}
			}
			if _, err := allocateRunnerEgress(state, "pn-123", cidr, "overflow", "overflow"); err == nil {
				t.Fatal("allocated gateway or broadcast")
			}
			delete(state.Machines, "2")
			got, err := allocateRunnerEgress(state, "pn-123", cidr, "replacement", "replacement")
			if err != nil || got.Address != "198.51.100.2" {
				t.Fatal("confirmed release not reused", got, err)
			}
		})
	}
	for _, cidr := range []string{"10.0.0.0/29", "100.64.0.0/29", "169.254.1.0/29", "127.0.0.0/29", "224.0.0.0/29", "::/29", "198.51.100.1/29", "198.51.100.0/30", "198.51.100.0/23"} {
		if _, _, err := runnerEgressPrefix("pn-123", cidr); err == nil {
			t.Fatalf("accepted %s", cidr)
		}
	}
	for _, network := range []string{"pn-test", "pn-123\n", "pn-1;bad", ""} {
		if _, _, err := runnerEgressPrefix(network, "198.51.100.0/29"); err == nil {
			t.Fatal("accepted", network)
		}
	}
	state := &runnerEgressReservations{}
	_, _ = allocateRunnerEgress(state, "pn-123", "198.51.100.0/29", "a", "server-a")
	for _, args := range [][4]string{
		{"pn-124", "198.51.100.0/29", "a", "server-a"},
		{"pn-123", "198.51.100.8/29", "a", "server-a"},
		{"pn-123", "198.51.100.0/29", "a", "server-b"},
		{"pn-123", "198.51.100.0/29", "b", "server-a"},
	} {
		if _, err := allocateRunnerEgress(state, args[0], args[1], args[2], args[3]); err == nil {
			t.Fatal("accepted unsafe transition", args)
		}
	}
	for _, address := range []string{"198.51.100.0", "198.51.100.6", "198.51.100.7", "198.51.100.8", "198.51.100.1"} {
		state.Machines["b"] = runnerEgressReservation{Service: "server-b", Address: address}
		if _, err := allocateRunnerEgress(state, "pn-123", "198.51.100.0/29", "c", "server-c"); err == nil {
			t.Fatal("accepted invalid/duplicate reservation", address)
		}
	}
}

type runnerEgressAPI struct {
	fakeOVHAPI
	attached bool
}

func (f *runnerEgressAPI) GetWithContext(_ context.Context, path string, out any) error {
	var body any
	switch {
	case strings.Contains(path, "?linkType=private"):
		body = []string{"aa:bb:cc:dd:ee:01"}
	case strings.HasSuffix(path, "/aa:bb:cc:dd:ee:01"):
		body = map[string]string{"virtualNetworkInterface": "vni-1"}
	case strings.HasSuffix(path, "/vni-1"):
		network := ""
		if f.attached {
			network = "pn-123"
		}
		body = map[string]any{"enabled": true, "mode": "vrack", "vrack": network}
	default:
		return fmt.Errorf("unexpected API read %s", path)
	}
	data, _ := json.Marshal(body)
	return json.Unmarshal(data, out)
}

type runnerEgressHarness struct {
	r         *OVHDedicatedMachineReconciler
	machine   *infrav1.OVHDedicatedMachine
	node      *corev1.Node
	api       *runnerEgressAPI
	scripts   []string
	scriptErr error
}

func newRunnerEgressHarness(t *testing.T) *runnerEgressHarness {
	t.Helper()
	h := &runnerEgressHarness{}
	h.machine = &infrav1.OVHDedicatedMachine{ObjectMeta: metav1.ObjectMeta{Name: "runner-a", Namespace: "staging", UID: "machine-a"}, Spec: infrav1.OVHDedicatedMachineSpec{KataRuntime: true}, Status: infrav1.OVHDedicatedMachineStatus{ServiceName: "server-a"}}
	h.node = &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: h.machine.Name, Labels: map[string]string{corev1.LabelHostname: h.machine.Name}}, Status: corev1.NodeStatus{NodeInfo: corev1.NodeSystemInfo{BootID: "boot-a"}}}
	cm := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: "runner-egress", Namespace: "staging"}, Data: map[string]string{"enabled": "true", "vrackID": "pn-123", "cidr": "198.51.100.0/29"}}
	c := fake.NewClientBuilder().WithScheme(releaseScheme(t)).WithObjects(h.machine, h.node, cm).Build()
	h.api = &runnerEgressAPI{attached: true}
	h.r = &OVHDedicatedMachineReconciler{Client: c, OVHClient: &ovh.Client{API: h.api}, RunnerEgressConfigName: cm.Name, RunnerEgressNamespace: cm.Namespace, RunnerEgressRunScript: func(_ context.Context, _ *infrav1.OVHDedicatedMachine, script string) error {
		h.scripts = append(h.scripts, script)
		return h.scriptErr
	}}
	return h
}
func (h *runnerEgressHarness) reconcile() error {
	return h.r.reconcileRunnerEgress(context.Background(), h.machine, h.node)
}
func (h *runnerEgressHarness) state(t *testing.T) *runnerEgressReservations {
	t.Helper()
	_, state, err := h.r.runnerEgressState(context.Background(), h.machine.Namespace)
	if err != nil {
		t.Fatal(err)
	}
	return state
}
func (h *runnerEgressHarness) config(t *testing.T, enabled bool) {
	t.Helper()
	cm := &corev1.ConfigMap{}
	if err := h.r.Get(context.Background(), types.NamespacedName{Namespace: "staging", Name: "runner-egress"}, cm); err != nil {
		t.Fatal(err)
	}
	cm.Data["enabled"] = fmt.Sprint(enabled)
	if err := h.r.Update(context.Background(), cm); err != nil {
		t.Fatal(err)
	}
}
func (h *runnerEgressHarness) policy(t *testing.T) *unstructured.Unstructured {
	t.Helper()
	p := runnerEgressPolicy(h.machine)
	if err := h.r.Get(context.Background(), client.ObjectKeyFromObject(p), p); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestRunnerEgressPublishesAfterHostConfigurationAndRepairsPolicy(t *testing.T) {
	h := newRunnerEgressHarness(t)
	h.api.attached = false
	if err := h.reconcile(); err == nil || len(h.scripts) != 0 {
		t.Fatal("configured an unattached NIC", err)
	}
	h.api.attached = true
	h.scriptErr = errors.New("uncertain SSH completion")
	if err := h.reconcile(); err == nil {
		t.Fatal("ignored SSH failure")
	}
	p := runnerEgressPolicy(h.machine)
	if err := h.r.Get(context.Background(), client.ObjectKeyFromObject(p), p); !apierrors.IsNotFound(err) {
		t.Fatal("published before host config", err)
	}
	if h.state(t).Machines[string(h.machine.UID)].MAC == "" {
		t.Fatal("lost uncertain SSH cleanup intent")
	}
	h.scriptErr = nil
	if err := h.reconcile(); err != nil {
		t.Fatal(err)
	}
	if !conditions.IsTrue(h.machine, runnerEgressReady) || h.node.Annotations[runnerEgressAddress] != "198.51.100.1" {
		t.Fatal("missing readiness/address")
	}
	p = h.policy(t)
	selectors, _, _ := unstructured.NestedSlice(p.Object, "spec", "selectors")
	selector := selectors[0].(map[string]any)
	podLabels, _, _ := unstructured.NestedStringMap(selector, "podSelector", "matchLabels")
	nodeLabels, _, _ := unstructured.NestedStringMap(selector, "nodeSelector", "matchLabels")
	if podLabels["io.kubernetes.pod.namespace"] != "tuist-runners" || podLabels["tuist.dev/runner"] != "true" || nodeLabels[corev1.LabelHostname] != h.node.Name {
		t.Fatal("unbounded pod selector", selector)
	}
	if len(p.GetOwnerReferences()) != 0 || p.GetNamespace() != "" {
		t.Fatal("cluster-scoped policy has namespaced ownership")
	}
	gateway, _, _ := unstructured.NestedString(p.Object, "spec", "egressGateway", "egressIP")
	if gateway != h.node.Annotations[runnerEgressAddress] {
		t.Fatal("wrong gateway IP")
	}
	calls := len(h.scripts)
	if err := h.reconcile(); err != nil || len(h.scripts) != calls {
		t.Fatal("steady state reconfigured host", err)
	}
	if err := h.r.Delete(context.Background(), p); err != nil {
		t.Fatal(err)
	}
	if err := h.reconcile(); err != nil || len(h.scripts) != calls {
		t.Fatal("policy repair failed", err)
	}
	oldRevision := h.policy(t).GetAnnotations()[runnerEgressRevision]
	h.node.Status.NodeInfo.BootID = "boot-b"
	if err := h.reconcile(); err != nil || len(h.scripts) != calls+1 {
		t.Fatal("reboot did not reconfigure", err)
	}
	if h.policy(t).GetAnnotations()[runnerEgressRevision] == oldRevision {
		t.Fatal("reboot did not refresh Cilium device selection")
	}
}

func TestRunnerEgressRollbackRetainsAddressUntilCleanupSucceeds(t *testing.T) {
	h := newRunnerEgressHarness(t)
	if err := h.reconcile(); err != nil {
		t.Fatal(err)
	}
	h.config(t, false)
	calls := len(h.scripts)
	if err := h.reconcile(); err == nil || len(h.scripts) != calls {
		t.Fatal("did not wait for policy withdrawal", err)
	}
	h.scriptErr = errors.New("host unreachable")
	if err := h.reconcile(); err == nil || len(h.state(t).Machines) != 1 {
		t.Fatal("failed cleanup recycled address", err)
	}
	h.scriptErr = nil
	if err := h.reconcile(); err != nil {
		t.Fatal(err)
	}
	if len(h.state(t).Machines) != 0 || conditions.Has(h.machine, runnerEgressReady) {
		t.Fatal("rollback did not release reservation/condition")
	}
	if !strings.Contains(h.scripts[len(h.scripts)-1], "if [ 'remove' = remove ]") {
		t.Fatal("did not render removal")
	}
	node := &corev1.Node{}
	if err := h.r.Get(context.Background(), client.ObjectKeyFromObject(h.node), node); err != nil {
		t.Fatal(err)
	}
	if node.Annotations[runnerEgressAddress] != "" {
		t.Fatal("stale Node address")
	}
}

func TestRunnerEgressDisabledAndNonRunnerAreInert(t *testing.T) {
	for _, mode := range []string{"disabled", "cache", "other namespace", "unconfigured"} {
		t.Run(mode, func(t *testing.T) {
			h := newRunnerEgressHarness(t)
			switch mode {
			case "disabled":
				h.config(t, false)
			case "cache":
				h.machine.Spec.KataRuntime = false
			case "other namespace":
				h.machine.Namespace = "other"
			case "unconfigured":
				h.r.RunnerEgressConfigName = ""
			}
			h.r.OVHClient = nil
			if err := h.reconcile(); err != nil || len(h.scripts) > 0 {
				t.Fatal("inactive config performed work", err)
			}
		})
	}
}

func TestRunnerEgressReservationWriteFailurePreventsHostMutation(t *testing.T) {
	h := newRunnerEgressHarness(t)
	h.r.Client = interceptor.NewClient(h.r.Client.(client.WithWatch), interceptor.Funcs{Create: func(ctx context.Context, c client.WithWatch, obj client.Object, opts ...client.CreateOption) error {
		if _, ok := obj.(*corev1.ConfigMap); ok {
			return errors.New("reservation rejected")
		}
		return c.Create(ctx, obj, opts...)
	}})
	if err := h.reconcile(); err == nil || len(h.scripts) > 0 {
		t.Fatal("configured without durable reservation", err)
	}
}

func TestRunnerEgressRejectsUnownedPolicy(t *testing.T) {
	h := newRunnerEgressHarness(t)
	p := runnerEgressPolicy(h.machine)
	if err := h.r.Create(context.Background(), p); err != nil {
		t.Fatal(err)
	}
	if err := h.reconcile(); err == nil || !strings.Contains(err.Error(), "unowned") {
		t.Fatal("overwrote unowned policy", err)
	}
	if err := h.r.cleanupRunnerEgress(context.Background(), h.machine); err == nil || len(h.state(t).Machines) != 1 {
		t.Fatal("deleted unowned policy", err)
	}
}

func TestRunnerEgressScriptSyntax(t *testing.T) {
	for _, remove := range []bool{false, true} {
		script, err := renderRunnerEgressScript(runnerEgressReservation{MAC: "aa:bb:cc:dd:ee:01", Address: "198.51.100.1"}, "pn-123", "198.51.100.0/29", remove)
		if err != nil {
			t.Fatal(err)
		}
		command := exec.Command("bash", "-n")
		command.Stdin = strings.NewReader(script)
		if output, err := command.CombinedOutput(); err != nil {
			t.Fatalf("syntax: %v %s", err, output)
		}
		if strings.Contains(script, "@") || !strings.Contains(script, "198.51.100.6") {
			t.Fatal("unrendered script or wrong gateway")
		}
	}
}

func TestRunnerEgressRefusesExistingPrivateNetwork(t *testing.T) {
	h := newRunnerEgressHarness(t)
	h.node.Annotations = map[string]string{privateNetworkAnnotation: "pn-999"}
	if err := h.reconcile(); err == nil || !strings.Contains(err.Error(), "already uses private network") {
		t.Fatal("accepted conflicting vRack", err)
	}
	if len(h.state(t).Machines) != 0 || len(h.scripts) != 0 {
		t.Fatal("mutated conflicting host")
	}
}

func TestRunnerEgressPreservesSharedPrivateNetwork(t *testing.T) {
	h := newRunnerEgressHarness(t)
	h.machine.Spec.VRackID = "pn-123"
	h.node.Annotations = map[string]string{privateNetworkAnnotation: "pn-123", privateNetworkRevision: "cache-revision"}
	if err := h.r.Update(context.Background(), h.node); err != nil {
		t.Fatal(err)
	}
	private := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: "private-network-reservations", Namespace: "staging"}, Data: map[string]string{"reservations.json": `{"network":"pn-123","cidr":"172.30.241.0/24","addresses":{"server-a":"172.30.241.4"}}`}}
	if err := h.r.Create(context.Background(), private); err != nil {
		t.Fatal(err)
	}
	if !privateNetworkOVHMachine(h.machine) {
		t.Fatal("shared-vRack runner lost private-network enrollment")
	}
	if err := h.reconcile(); err != nil {
		t.Fatal(err)
	}
	h.config(t, false)
	// The first pass withdraws the policy; the next confirms removal and cleans up.
	_ = h.reconcile()
	if err := h.reconcile(); err != nil {
		t.Fatal(err)
	}
	node := &corev1.Node{}
	if err := h.r.Get(context.Background(), client.ObjectKeyFromObject(h.node), node); err != nil {
		t.Fatal(err)
	}
	if node.Annotations[privateNetworkAnnotation] != "pn-123" || node.Annotations[privateNetworkRevision] != "cache-revision" || node.Annotations[runnerEgressAddress] != "" {
		t.Fatalf("egress rollback changed private-network identity: %v", node.Annotations)
	}
	after := &corev1.ConfigMap{}
	if err := h.r.Get(context.Background(), client.ObjectKeyFromObject(private), after); err != nil {
		t.Fatal(err)
	}
	if after.Data["reservations.json"] != private.Data["reservations.json"] {
		t.Fatal("egress rollback changed the retained private reservation")
	}
}

func TestRunnerEgressDeletionWaitsBeforeDroppingCredentials(t *testing.T) {
	h := newRunnerEgressHarness(t)
	if err := h.reconcile(); err != nil {
		t.Fatal(err)
	}
	// CredentialsManager is deliberately nil: reaching identity deletion before
	// policy/host cleanup would panic rather than quietly passing this test.
	if _, err := h.r.reconcileDelete(context.Background(), h.machine); err == nil {
		t.Fatal("deletion did not wait for policy withdrawal")
	}
	h.scriptErr = errors.New("host offline")
	if _, err := h.r.reconcileDelete(context.Background(), h.machine); err == nil {
		t.Fatal("deletion continued with host still configured")
	}
	if len(h.state(t).Machines) != 1 {
		t.Fatal("deletion freed an unconfirmed address")
	}
	node := &corev1.Node{}
	if err := h.r.Get(context.Background(), client.ObjectKeyFromObject(h.node), node); err != nil {
		t.Fatal("deleted Node before host cleanup", err)
	}
}
