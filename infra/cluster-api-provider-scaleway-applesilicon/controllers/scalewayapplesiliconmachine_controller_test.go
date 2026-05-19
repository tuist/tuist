package controllers

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
)

// recordUpdateFailure is the safety primitive that bounds the
// drift-loop's retry behaviour. Tests document the contract:
// counter increments per call; only crosses into the terminal
// FailureReason state once the cap is reached; cap=0 disables
// terminal transition entirely (escape hatch documented on the
// flag).

// fakeRecorder is the FakeRecorder from client-go but its full
// import path is a mouthful and tests don't read the events back —
// just need a recorder that doesn't panic on Eventf.
func fakeRecorder() record.EventRecorder {
	return record.NewFakeRecorder(32)
}

func TestRecordUpdateFailure_IncrementsAttempts(t *testing.T) {
	machine := &infrav1.ScalewayAppleSiliconMachine{}
	recordUpdateFailure(machine, errors.New("boom"), 5, logr.Discard(), fakeRecorder())
	if machine.Status.TartKubeletUpdateAttempts != 1 {
		t.Fatalf("attempts: got %d, want 1", machine.Status.TartKubeletUpdateAttempts)
	}
	if machine.Status.FailureReason != nil {
		t.Fatalf("did not expect terminal failure on attempt 1; got %q", *machine.Status.FailureReason)
	}
}

func TestRecordUpdateFailure_TransitionsToFailedAtCap(t *testing.T) {
	machine := &infrav1.ScalewayAppleSiliconMachine{}
	for i := 0; i < 5; i++ {
		recordUpdateFailure(machine, errors.New("boom"), 5, logr.Discard(), fakeRecorder())
	}
	if machine.Status.TartKubeletUpdateAttempts != 5 {
		t.Fatalf("attempts: got %d, want 5", machine.Status.TartKubeletUpdateAttempts)
	}
	if machine.Status.FailureReason == nil {
		t.Fatal("expected FailureReason to be set after 5 attempts")
	}
	if got, want := *machine.Status.FailureReason, "TartKubeletUpdateExceededRetries"; got != want {
		t.Fatalf("FailureReason: got %q, want %q", got, want)
	}
	if machine.Status.Phase != "Failed" {
		t.Fatalf("Phase: got %q, want Failed", machine.Status.Phase)
	}
	if machine.Status.FailureMessage == nil {
		t.Fatal("expected FailureMessage to be set")
	}
}

func TestRecordUpdateFailure_DoesNotTransitionBeforeCap(t *testing.T) {
	machine := &infrav1.ScalewayAppleSiliconMachine{}
	for i := 0; i < 4; i++ {
		recordUpdateFailure(machine, errors.New("boom"), 5, logr.Discard(), fakeRecorder())
	}
	if machine.Status.FailureReason != nil {
		t.Fatalf("did not expect terminal failure on attempt 4; got %q", *machine.Status.FailureReason)
	}
}

func TestRecordUpdateFailure_DisabledCap(t *testing.T) {
	machine := &infrav1.ScalewayAppleSiliconMachine{}
	for i := 0; i < 100; i++ {
		recordUpdateFailure(machine, errors.New("boom"), 0, logr.Discard(), fakeRecorder())
	}
	if machine.Status.TartKubeletUpdateAttempts != 100 {
		t.Fatalf("attempts: got %d, want 100", machine.Status.TartKubeletUpdateAttempts)
	}
	if machine.Status.FailureReason != nil {
		t.Fatalf("cap=0 must never trigger terminal failure; got %q", *machine.Status.FailureReason)
	}
}

// nodeMissingAfterBootstrap is the drift detector that lets an
// already-bootstrapped Machine recover when its Node disappears
// (typically: upstream CAPI core deleting the Node during workload-
// cluster reconcile churn). The contract: the operator returns true
// only when it's confident the Node should already be registered —
// after BootstrappedCondition has been True for nodeBootstrapGrace —
// otherwise it would race the initial post-bootstrap registration
// and falsely re-bootstrap a healthy Machine.

func TestNodeMissingAfterBootstrap_NotBootstrapped(t *testing.T) {
	r := newReconciler(t)
	machine := &infrav1.ScalewayAppleSiliconMachine{ObjectMeta: metav1.ObjectMeta{Name: "m1"}}
	missing, err := r.nodeMissingAfterBootstrap(context.Background(), machine)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if missing {
		t.Fatal("not yet bootstrapped: drift detector must not fire")
	}
}

func TestNodeMissingAfterBootstrap_WithinGrace(t *testing.T) {
	r := newReconciler(t)
	machine := &infrav1.ScalewayAppleSiliconMachine{ObjectMeta: metav1.ObjectMeta{Name: "m1"}}
	conditions.MarkTrue(machine, BootstrappedCondition)
	// Just-flipped condition simulates the post-bootstrap requeue
	// before tart-kubelet's first registration has propagated.
	missing, err := r.nodeMissingAfterBootstrap(context.Background(), machine)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if missing {
		t.Fatal("within grace window: drift detector must wait")
	}
}

func TestNodeMissingAfterBootstrap_NodeExists(t *testing.T) {
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "m1"}}
	r := newReconciler(t, node)
	machine := &infrav1.ScalewayAppleSiliconMachine{ObjectMeta: metav1.ObjectMeta{Name: "m1"}}
	conditions.MarkTrue(machine, BootstrappedCondition)
	backdateBootstrappedCondition(machine, 5*time.Minute)
	missing, err := r.nodeMissingAfterBootstrap(context.Background(), machine)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if missing {
		t.Fatal("Node present: drift detector must not fire")
	}
}

func TestNodeMissingAfterBootstrap_NodeGone(t *testing.T) {
	r := newReconciler(t)
	machine := &infrav1.ScalewayAppleSiliconMachine{ObjectMeta: metav1.ObjectMeta{Name: "m1"}}
	conditions.MarkTrue(machine, BootstrappedCondition)
	backdateBootstrappedCondition(machine, 5*time.Minute)
	missing, err := r.nodeMissingAfterBootstrap(context.Background(), machine)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !missing {
		t.Fatal("Node missing past grace: drift detector must fire to drive re-bootstrap")
	}
}

func newReconciler(t *testing.T, objs ...runtime.Object) *ScalewayAppleSiliconMachineReconciler {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatalf("scheme: %v", err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatalf("infrav1 scheme: %v", err)
	}
	if err := clusterv1.AddToScheme(scheme); err != nil {
		t.Fatalf("clusterv1 scheme: %v", err)
	}
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.ScalewayAppleSiliconMachine{}).
		Build()
	return &ScalewayAppleSiliconMachineReconciler{
		Client:   c,
		Recorder: fakeRecorder(),
	}
}

func backdateBootstrappedCondition(machine *infrav1.ScalewayAppleSiliconMachine, by time.Duration) {
	// Mutating Status.Conditions directly: conditions.Set preserves
	// LastTransitionTime when state hasn't changed, which would no-op
	// the backdate in this test setup.
	for i, c := range machine.Status.Conditions {
		if c.Type == BootstrappedCondition {
			machine.Status.Conditions[i].LastTransitionTime = metav1.NewTime(time.Now().Add(-by))
			return
		}
	}
}

// Pause-annotation contract:
//   - cluster.x-k8s.io/paused on the infra CR latches reconcileNormal
//     off, so out-of-band cleanup (clear status.ServerID +
//     spec.ProviderID before kubectl delete) can't race the
//     adoption loop. reconcileDelete still runs on DeletionTimestamp
//     regardless of the annotation — pause must not block teardown.

func TestReconcile_PausedAnnotationSkipsAdoption(t *testing.T) {
	machine := &infrav1.ScalewayAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "m1",
			Namespace: "ns",
			Annotations: map[string]string{
				"cluster.x-k8s.io/paused": "true",
			},
		},
		Spec: infrav1.ScalewayAppleSiliconMachineSpec{
			AdoptPoolPrefix: "tuist-pool-",
			Type:            "M2-L",
			Zone:            "fr-par-1",
			OS:              "macos-tahoe-26.3",
		},
	}
	r := newReconciler(t, machine)
	// Leaving r.ScalewayClient nil: if pause is honored, the
	// reconciler returns before any Scaleway call, so nothing
	// dereferences it. If pause is broken, the reconciler will
	// reach acquireServer and crash here — that's the failure
	// signal we want.
	result, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{Name: "m1", Namespace: "ns"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.RequeueAfter != 0 || result.Requeue {
		t.Fatalf("paused CR must not be requeued; got %+v", result)
	}

	// Status should be untouched — no AdoptByPrefix means no phase
	// transition into Adopting / Provisioning.
	got := &infrav1.ScalewayAppleSiliconMachine{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "m1", Namespace: "ns"}, got); err != nil {
		t.Fatalf("get machine: %v", err)
	}
	if got.Status.Phase != "" {
		t.Fatalf("paused CR phase should be untouched; got %q", got.Status.Phase)
	}
	if got.Status.ServerID != "" {
		t.Fatalf("paused CR must not have claimed a server; got %q", got.Status.ServerID)
	}
}

// reconcileTailscaleEgressService contract:
//   - empty EgressProxyGroup short-circuits (OSS shape unaffected)
//   - missing MagicDNSSuffix when proxy-group is set returns an error
//     instead of writing a malformed FQDN annotation
//   - create path stamps name, namespace, labels, annotations, ports
//   - update path is idempotent: re-running with no spec change is a
//     noop, and the operator's externalName rewrite isn't clobbered

func TestReconcileTailscaleEgressService_Disabled(t *testing.T) {
	r := newReconciler(t)
	// EgressProxyGroup unset → short-circuit, no Service created.
	machine := &infrav1.ScalewayAppleSiliconMachine{ObjectMeta: metav1.ObjectMeta{Name: "m1"}}
	if err := r.reconcileTailscaleEgressService(context.Background(), machine); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	svcs := &corev1.ServiceList{}
	if err := r.Client.List(context.Background(), svcs); err != nil {
		t.Fatalf("list services: %v", err)
	}
	if len(svcs.Items) != 0 {
		t.Fatalf("expected no services created when egress disabled, got %d", len(svcs.Items))
	}
}

func TestReconcileTailscaleEgressService_MissingSuffix(t *testing.T) {
	r := newReconciler(t)
	r.EgressProxyGroup = "macmini-egress"
	r.EgressNamespace = "tailscale-operator"
	// MagicDNSSuffix deliberately left empty: would produce
	// `<machine>.` as the FQDN, which the Tailscale operator
	// silently rejects. Fail loudly instead.
	machine := &infrav1.ScalewayAppleSiliconMachine{ObjectMeta: metav1.ObjectMeta{Name: "m1"}}
	if err := r.reconcileTailscaleEgressService(context.Background(), machine); err == nil {
		t.Fatal("expected error when MagicDNSSuffix is empty but proxy-group is set")
	}
}

func TestReconcileTailscaleEgressService_Create(t *testing.T) {
	r := newReconciler(t)
	r.EgressProxyGroup = "macmini-egress"
	r.EgressNamespace = "tailscale-operator"
	r.EgressMagicDNSSuffix = "taild6d7bb.ts.net"
	machine := &infrav1.ScalewayAppleSiliconMachine{ObjectMeta: metav1.ObjectMeta{Name: "macmini-1"}}
	if err := r.reconcileTailscaleEgressService(context.Background(), machine); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	got := &corev1.Service{}
	if err := r.Client.Get(context.Background(),
		types.NamespacedName{Namespace: "tailscale-operator", Name: "macmini-1"}, got); err != nil {
		t.Fatalf("get created service: %v", err)
	}
	if got.Spec.Type != corev1.ServiceTypeExternalName {
		t.Errorf("Spec.Type = %q, want ExternalName", got.Spec.Type)
	}
	if got.Annotations["tailscale.com/tailnet-fqdn"] != "macmini-1.taild6d7bb.ts.net" {
		t.Errorf("tailnet-fqdn = %q, want macmini-1.taild6d7bb.ts.net",
			got.Annotations["tailscale.com/tailnet-fqdn"])
	}
	if got.Annotations["tailscale.com/proxy-group"] != "macmini-egress" {
		t.Errorf("proxy-group = %q, want macmini-egress",
			got.Annotations["tailscale.com/proxy-group"])
	}
	if got.Labels["tuist.dev/macmini-egress"] != "true" {
		t.Errorf("macmini-egress label = %q, want true", got.Labels["tuist.dev/macmini-egress"])
	}
	if len(got.Spec.Ports) != 2 {
		t.Fatalf("Spec.Ports len = %d, want 2", len(got.Spec.Ports))
	}
	// Ports must include node-exporter:9100 and tart-kubelet:8080 —
	// the named ports alloy-metrics filters on.
	portByName := map[string]int32{}
	for _, p := range got.Spec.Ports {
		portByName[p.Name] = p.Port
	}
	if portByName["node-exporter"] != 9100 {
		t.Errorf("node-exporter port = %d, want 9100", portByName["node-exporter"])
	}
	if portByName["tart-kubelet"] != 8080 {
		t.Errorf("tart-kubelet port = %d, want 8080", portByName["tart-kubelet"])
	}
}

func TestReconcileTailscaleEgressService_IdempotentAndPreservesOperatorRewrite(t *testing.T) {
	r := newReconciler(t)
	r.EgressProxyGroup = "macmini-egress"
	r.EgressNamespace = "tailscale-operator"
	r.EgressMagicDNSSuffix = "taild6d7bb.ts.net"
	machine := &infrav1.ScalewayAppleSiliconMachine{ObjectMeta: metav1.ObjectMeta{Name: "macmini-1"}}

	// First reconcile creates the Service with the placeholder
	// externalName.
	if err := r.reconcileTailscaleEgressService(context.Background(), machine); err != nil {
		t.Fatalf("first reconcile: %v", err)
	}

	// Simulate the Tailscale operator rewriting externalName to point
	// at the ClusterIP fronting the ProxyGroup — this is what happens
	// in a real cluster moments after the Service is admitted.
	got := &corev1.Service{}
	key := types.NamespacedName{Namespace: "tailscale-operator", Name: "macmini-1"}
	if err := r.Client.Get(context.Background(), key, got); err != nil {
		t.Fatalf("get after create: %v", err)
	}
	got.Spec.ExternalName = "ts-macmini-egress.tailscale-operator.svc.cluster.local"
	if err := r.Client.Update(context.Background(), got); err != nil {
		t.Fatalf("simulate operator rewrite: %v", err)
	}

	// Second reconcile must NOT clobber externalName — otherwise the
	// operator and the CAPI controller fight forever, each
	// re-stamping their own value every reconcile cycle.
	if err := r.reconcileTailscaleEgressService(context.Background(), machine); err != nil {
		t.Fatalf("second reconcile: %v", err)
	}
	if err := r.Client.Get(context.Background(), key, got); err != nil {
		t.Fatalf("get after re-reconcile: %v", err)
	}
	if got.Spec.ExternalName != "ts-macmini-egress.tailscale-operator.svc.cluster.local" {
		t.Errorf("re-reconcile clobbered operator's externalName rewrite (now %q)",
			got.Spec.ExternalName)
	}
}
