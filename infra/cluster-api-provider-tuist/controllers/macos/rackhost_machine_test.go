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

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const (
	testCluster = "tuist-tuist-capi"
	// testHostMachine is <fleet>-<host> for mini-01.
	testHostMachine = testFleet + "-mini-01"
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
	r := newRackMachinesReconciler(t, unmachinedHost())
	reconcileHost(t, r, "mini-01")

	machine, _ := getMachine(t, r, testHostMachine)
	machine.Finalizers = []string{clusterv1.MachineFinalizer}
	if err := r.Update(context.Background(), machine); err != nil {
		t.Fatalf("add finalizer: %v", err)
	}
	if err := r.Delete(context.Background(), machine); err != nil {
		t.Fatalf("delete Machine: %v", err)
	}
	terminating, _ := getMachine(t, r, testHostMachine)
	labels := copyLabels(terminating.Labels)

	res := reconcileHost(t, r, "mini-01")

	if res.RequeueAfter != rackMachineDeletingRequeue {
		t.Fatalf("result %+v, want a requeue while the Machine goes", res)
	}
	still, _ := getMachine(t, r, testHostMachine)
	if still.DeletionTimestamp.IsZero() || len(still.Labels) != len(labels) {
		t.Fatal("patched or replaced a terminating Machine")
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
