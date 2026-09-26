package macos

import (
	"context"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	"k8s.io/utils/ptr"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	ctrl "sigs.k8s.io/controller-runtime"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const (
	testCluster = "tuist-tuist-capi"
	// testHostMachine is <fleet>-<host> for mini-01.
	testHostMachine = testFleet + "-mini-01"
	// testMachineSetMachine is a Machine a MachineSet made for mini-01.
	testMachineSetMachine = "tuist-tuist-rack-fleet-8k5ht-hhrfm"
	testProviderID        = "rack-applesilicon://ber1/C07FC05JQ6NY"
)

func newRackMachinesReconciler(t *testing.T, objs ...runtime.Object) *RackHostReconciler {
	t.Helper()
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, objs...)
	r.Machines = &RackMachines{ClusterName: testCluster, BootstrapSecret: "tuist-tuist-noop-bootstrap", FleetName: testFleet}
	return r
}

func unmachinedHost(mutate ...func(*infrav1.RackHost)) *infrav1.RackHost {
	return rackHost("mini-01", append([]func(*infrav1.RackHost){func(h *infrav1.RackHost) {
		h.Status.Machine = ""
		h.Spec.Machine = infrav1.RackHostMachine{HostCPU: 8, HostMemoryMB: 14336, GuestCapacity: 1, MaxPods: 3, RunnerCacheVolumeGiB: ptr.To(0)}
	}}, mutate...)...)
}

// machineSetMachine is the Machine and RackAppleSiliconMachine a rack fleet's
// MachineSet made and bound to mini-01, as they are in a live cluster.
func machineSetMachine(mutate ...func(*clusterv1.Machine)) (*clusterv1.Machine, *infrav1.RackAppleSiliconMachine) {
	msLabels := map[string]string{
		clusterv1.ClusterNameLabel:             testCluster,
		clusterv1.MachineDeploymentNameLabel:   "tuist-tuist-rack-fleet",
		clusterv1.MachineSetNameLabel:          "tuist-tuist-rack-fleet-8k5ht",
		clusterv1.MachineDeploymentUniqueLabel: "3013903975-8k5ht",
		"tuist.dev/fleet":                      testFleet,
	}
	secret := "tuist-tuist-noop-bootstrap"
	machine := &clusterv1.Machine{
		ObjectMeta: metav1.ObjectMeta{
			Name: testMachineSetMachine, Namespace: testNamespace, Labels: copyLabels(msLabels),
			Finalizers: []string{clusterv1.MachineFinalizer},
			OwnerReferences: []metav1.OwnerReference{{
				APIVersion: clusterv1.GroupVersion.String(), Kind: "MachineSet", Name: "tuist-tuist-rack-fleet-8k5ht",
				UID: "c8b5709b", Controller: ptr.To(true), BlockOwnerDeletion: ptr.To(true),
			}},
		},
		Spec: clusterv1.MachineSpec{
			ClusterName: testCluster,
			Bootstrap:   clusterv1.Bootstrap{DataSecretName: &secret},
			InfrastructureRef: corev1.ObjectReference{
				APIVersion: infrav1.GroupVersion.String(), Kind: "RackAppleSiliconMachine",
				Name: testMachineSetMachine, Namespace: testNamespace,
			},
			ProviderID: ptr.To(testProviderID),
		},
		Status: clusterv1.MachineStatus{NodeRef: &corev1.ObjectReference{Kind: "Node", Name: testMachineSetMachine}},
	}
	for _, m := range mutate {
		m(machine)
	}
	infra := &infrav1.RackAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{
			Name: testMachineSetMachine, Namespace: testNamespace, Labels: copyLabels(msLabels),
			OwnerReferences: []metav1.OwnerReference{{
				APIVersion: clusterv1.GroupVersion.String(), Kind: "Machine", Name: testMachineSetMachine,
				UID: "5c6e0708", Controller: ptr.To(true),
			}},
		},
		Spec: infrav1.RackAppleSiliconMachineSpec{
			FleetName: testFleet, ProviderID: ptr.To(testProviderID),
			HostCPU: 8, HostMemoryMB: 14336, GuestCapacity: 1, MaxPods: 3, RunnerCacheVolumeGiB: ptr.To(0),
		},
		Status: infrav1.RackAppleSiliconMachineStatus{Ready: true},
	}
	return machine, infra
}

func copyLabels(in map[string]string) map[string]string {
	out := map[string]string{}
	for k, v := range in {
		out[k] = v
	}
	return out
}

func getMachine(t *testing.T, r *RackHostReconciler, name string) (*clusterv1.Machine, bool) {
	t.Helper()
	m := &clusterv1.Machine{}
	err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: name}, m)
	if apierrors.IsNotFound(err) {
		return nil, false
	}
	if err != nil {
		t.Fatalf("get Machine %s: %v", name, err)
	}
	return m, true
}

func getInfraMachine(t *testing.T, r *RackHostReconciler, name string) (*infrav1.RackAppleSiliconMachine, bool) {
	t.Helper()
	m := &infrav1.RackAppleSiliconMachine{}
	err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: name}, m)
	if apierrors.IsNotFound(err) {
		return nil, false
	}
	if err != nil {
		t.Fatalf("get RackAppleSiliconMachine %s: %v", name, err)
	}
	return m, true
}

func hostEvents(r *RackHostReconciler) []string {
	rec := r.Recorder.(*record.FakeRecorder)
	var out []string
	for {
		select {
		case e := <-rec.Events:
			out = append(out, e)
		default:
			return out
		}
	}
}

func countEvents(events []string, reason string) int {
	n := 0
	for _, e := range events {
		if strings.Contains(e, " "+reason+" ") {
			n++
		}
	}
	return n
}

func TestRackHostKeepsTheMachineThatMakesItANode(t *testing.T) {
	r := newRackMachinesReconciler(t, unmachinedHost())

	reconcileHost(t, r, "mini-01")
	reconcileHost(t, r, "mini-01")

	if got := readHost(t, r, "mini-01").Status.Machine; got != testHostMachine {
		t.Fatalf("status.machine = %q, want %q", got, testHostMachine)
	}
	infra, ok := getInfraMachine(t, r, testHostMachine)
	if !ok {
		t.Fatal("no RackAppleSiliconMachine")
	}
	if infra.Spec.Host != "mini-01" || infra.Spec.FleetName != testFleet {
		t.Fatalf("RackAppleSiliconMachine spec %+v", infra.Spec)
	}
	if infra.Spec.HostCPU != 8 || infra.Spec.MaxPods != 3 || ptr.Deref(infra.Spec.RunnerCacheVolumeGiB, -1) != 0 {
		t.Fatalf("sizing %+v, want the host's", infra.Spec)
	}

	machine, ok := getMachine(t, r, testHostMachine)
	if !ok {
		t.Fatal("no Machine")
	}
	if machine.Spec.ClusterName != testCluster || ptr.Deref(machine.Spec.Bootstrap.DataSecretName, "") != "tuist-tuist-noop-bootstrap" {
		t.Fatalf("Machine spec %+v", machine.Spec)
	}
	if ref := machine.Spec.InfrastructureRef; ref.Kind != "RackAppleSiliconMachine" || ref.Name != testHostMachine {
		t.Fatalf("infrastructureRef %+v", ref)
	}
	// The fleet label is what the fleet's MachineHealthCheck selects on.
	if machine.Labels["tuist.dev/fleet"] != testFleet || machine.Labels[clusterv1.ClusterNameLabel] != testCluster || machine.Labels[RackHostLabel] != "mini-01" {
		t.Fatalf("labels %v", machine.Labels)
	}
	owner := metav1.GetControllerOf(machine)
	if owner == nil || owner.Kind != "RackHost" || owner.Name != "mini-01" {
		t.Fatalf("controller %+v, want the host", owner)
	}
	if n := countEvents(hostEvents(r), "MachineCreated"); n != 1 {
		t.Fatalf("%d MachineCreated events, want one across two reconciles", n)
	}
}

// A Machine a MachineSet made for this box keeps its name and its Node: only
// its owner changes, so the MachineSet neither deletes it nor counts it.
func TestRackHostAdoptsTheMachineItsBoxAlreadyIs(t *testing.T) {
	machine, infra := machineSetMachine()
	r := newRackMachinesReconciler(t, unmachinedHost(), machine, infra)

	reconcileHost(t, r, "mini-01")

	if got := readHost(t, r, "mini-01").Status.Machine; got != testMachineSetMachine {
		t.Fatalf("status.machine = %q, want the adopted %q", got, testMachineSetMachine)
	}
	if _, made := getMachine(t, r, testHostMachine); made {
		t.Fatal("made a second Machine for a box that already has one")
	}
	adopted, ok := getMachine(t, r, testMachineSetMachine)
	if !ok {
		t.Fatal("the adopted Machine is gone")
	}
	for _, ref := range adopted.OwnerReferences {
		if ref.Kind == "MachineSet" {
			t.Fatalf("still owned by MachineSet %s; scaling it to 0 would delete the host's Node", ref.Name)
		}
	}
	if owner := metav1.GetControllerOf(adopted); owner == nil || owner.Kind != "RackHost" || owner.Name != "mini-01" {
		t.Fatalf("controller %+v, want the host", owner)
	}
	for _, label := range machineSetLabels {
		if _, still := adopted.Labels[label]; still {
			t.Fatalf("still carries %s; the MachineSet selects it", label)
		}
	}
	if adopted.Status.NodeRef == nil || adopted.Status.NodeRef.Name != testMachineSetMachine || !adopted.DeletionTimestamp.IsZero() {
		t.Fatal("adoption touched the Machine's Node binding")
	}
	if ptr.Deref(adopted.Spec.ProviderID, "") != testProviderID || adopted.Spec.InfrastructureRef.Name != testMachineSetMachine {
		t.Fatalf("adoption changed the Machine's spec: %+v", adopted.Spec)
	}

	adoptedInfra, _ := getInfraMachine(t, r, testMachineSetMachine)
	if adoptedInfra.Spec.Host != "mini-01" || !adoptedInfra.Status.Ready {
		t.Fatalf("RackAppleSiliconMachine %+v / ready %t, want it to name its host and stay ready", adoptedInfra.Spec, adoptedInfra.Status.Ready)
	}
	for _, label := range machineSetLabels {
		if _, still := adoptedInfra.Labels[label]; still {
			t.Fatalf("RackAppleSiliconMachine still carries %s", label)
		}
	}
	if n := countEvents(hostEvents(r), "MachineAdopted"); n != 1 {
		t.Fatalf("%d MachineAdopted events, want one", n)
	}
}

// A MachineSet's Machine with no providerID yet is not this box, whatever it
// is called.
func TestRackHostDoesNotAdoptAMachineThatIsNotItsBox(t *testing.T) {
	machine, infra := machineSetMachine(func(m *clusterv1.Machine) { m.Spec.ProviderID = nil })
	r := newRackMachinesReconciler(t, unmachinedHost(), machine, infra)

	reconcileHost(t, r, "mini-01")

	if got := readHost(t, r, "mini-01").Status.Machine; got != testHostMachine {
		t.Fatalf("status.machine = %q, want its own %q", got, testHostMachine)
	}
	msMachine, _ := getMachine(t, r, testMachineSetMachine)
	if owner := metav1.GetControllerOf(msMachine); owner == nil || owner.Kind != "MachineSet" {
		t.Fatalf("took over a MachineSet's Machine that is not this box: %+v", owner)
	}
}

// Two hosts that declare one box would give it two Machines fighting over one
// Node.
func TestRackHostWhoseBoxAnotherHostHasGetsNoMachine(t *testing.T) {
	machine, infra := machineSetMachine(func(m *clusterv1.Machine) {
		m.OwnerReferences = []metav1.OwnerReference{{
			APIVersion: infrav1.GroupVersion.String(), Kind: "RackHost", Name: "mini-99", UID: "u", Controller: ptr.To(true),
		}}
	})
	r := newRackMachinesReconciler(t, unmachinedHost(), machine, infra)

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: testNamespace, Name: "mini-01"}}); err == nil {
		t.Fatal("reconciled a host whose box another host already has")
	}
	if _, made := getMachine(t, r, testHostMachine); made {
		t.Fatal("made a second Machine for the box")
	}
	if n := countEvents(hostEvents(r), "DuplicateHost"); n != 1 {
		t.Fatalf("%d DuplicateHost events, want one", n)
	}
}

func TestParkedHostHasNoMachine(t *testing.T) {
	host := unmachinedHost()
	r := newRackMachinesReconciler(t, host)
	reconcileHost(t, r, "mini-01")

	parked := readHost(t, r, "mini-01")
	parked.Spec.Parked = true
	if err := r.Update(context.Background(), parked); err != nil {
		t.Fatalf("park: %v", err)
	}
	res := reconcileHost(t, r, "mini-01")
	if res.RequeueAfter != rackMachineDeletingRequeue {
		t.Fatalf("result %+v, want a requeue while the Machine goes", res)
	}
	if _, still := getMachine(t, r, testHostMachine); still {
		t.Fatal("a parked host kept its Machine")
	}
	reconcileHost(t, r, "mini-01")
	reconcileHost(t, r, "mini-01")
	if _, still := getInfraMachine(t, r, testHostMachine); still {
		t.Fatal("a parked host kept its RackAppleSiliconMachine")
	}
	if _, made := getMachine(t, r, testHostMachine); made {
		t.Fatal("a parked host got a Machine again")
	}
}

// A MachineHealthCheck only marks an unhealthy Machine; its owner remediates
// it. For a rack host that is a new Machine on the same box.
func TestUnhealthyMachineIsDeletedAndMadeAgain(t *testing.T) {
	r := newRackMachinesReconciler(t, unmachinedHost())
	reconcileHost(t, r, "mini-01")

	machine, _ := getMachine(t, r, testHostMachine)
	machine.Status.Conditions = clusterv1.Conditions{
		{Type: clusterv1.MachineHealthCheckSucceededCondition, Status: corev1.ConditionFalse, Reason: clusterv1.UnhealthyNodeConditionReason, Message: "Condition Ready on node is reporting status False for more than 30m0s"},
		{Type: clusterv1.MachineOwnerRemediatedCondition, Status: corev1.ConditionFalse, Reason: clusterv1.WaitingForRemediationReason},
	}
	if err := r.Status().Update(context.Background(), machine); err != nil {
		t.Fatalf("mark unhealthy: %v", err)
	}
	reconcileHost(t, r, "mini-01")
	if _, still := getMachine(t, r, testHostMachine); still {
		t.Fatal("the unhealthy Machine was not deleted")
	}
	if n := countEvents(hostEvents(r), "MachineRemediated"); n != 1 {
		t.Fatalf("%d MachineRemediated events, want one", n)
	}

	reconcileHost(t, r, "mini-01")
	again, ok := getMachine(t, r, testHostMachine)
	if !ok || len(again.Status.Conditions) != 0 {
		t.Fatal("the host got no new Machine")
	}
}

// While a Machine is going, the host waits for it rather than patching a
// terminating object or making a second one.
func TestHostWaitsForItsMachineToGo(t *testing.T) {
	machine, infra := machineSetMachine(func(m *clusterv1.Machine) { m.DeletionTimestamp = ptr.To(metav1.Now()) })
	host := unmachinedHost(func(h *infrav1.RackHost) { h.Status.Machine = testMachineSetMachine })
	r := newRackMachinesReconciler(t, host, machine, infra)

	res := reconcileHost(t, r, "mini-01")

	if res.RequeueAfter != rackMachineDeletingRequeue {
		t.Fatalf("result %+v, want a requeue while the Machine goes", res)
	}
	still, _ := getMachine(t, r, testMachineSetMachine)
	if owner := metav1.GetControllerOf(still); owner == nil || owner.Kind != "MachineSet" {
		t.Fatal("patched a terminating Machine")
	}
	if _, made := getMachine(t, r, testHostMachine); made {
		t.Fatal("made a second Machine while the first was still going")
	}
}

// Sizing reaches the host through its RackAppleSiliconMachine, which the drift
// loop pushes.
func TestHostSizingReachesItsMachine(t *testing.T) {
	r := newRackMachinesReconciler(t, unmachinedHost())
	reconcileHost(t, r, "mini-01")

	host := readHost(t, r, "mini-01")
	host.Spec.Machine.HostCPU = 12
	host.Spec.Machine.RunnerCacheVolumeGiB = nil
	if err := r.Update(context.Background(), host); err != nil {
		t.Fatalf("resize: %v", err)
	}
	reconcileHost(t, r, "mini-01")

	infra, _ := getInfraMachine(t, r, testHostMachine)
	if infra.Spec.HostCPU != 12 || infra.Spec.RunnerCacheVolumeGiB != nil {
		t.Fatalf("sizing %+v, want hostCPU 12 and the default cache volume", infra.Spec)
	}
}

func TestNoMachinesWithoutTheirCluster(t *testing.T) {
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, unmachinedHost())

	reconcileHost(t, r, "mini-01")

	if _, made := getMachine(t, r, testHostMachine); made {
		t.Fatal("made a Machine with no cluster to make it in")
	}
	if got := readHost(t, r, "mini-01").Status.Machine; got != "" {
		t.Fatalf("status.machine = %q with no Machines kept", got)
	}
}
