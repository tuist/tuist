package controllers

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/go-logr/logr"
	applesilicon "github.com/scaleway/scaleway-sdk-go/api/applesilicon/v1alpha1"
	"github.com/scaleway/scaleway-sdk-go/scw"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/scaleway"
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
	if err := rbacv1.AddToScheme(scheme); err != nil {
		t.Fatalf("rbacv1 scheme: %v", err)
	}
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.ScalewayAppleSiliconMachine{}).
		Build()
	return &ScalewayAppleSiliconMachineReconciler{
		Client:   c,
		Recorder: fakeRecorder(),
		// Real CredentialsManager backed by the same fake client. The
		// per-machine Delete methods tolerate IsNotFound, so reconcileDelete
		// can flow through Stages 2-3 without any pre-staged Secret /
		// ServiceAccount / ClusterRoleBinding fixtures.
		CredentialsManager: &credentials.Manager{
			Client:    c,
			Namespace: "ns",
		},
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

	// Status should be untouched — no AdoptFromPool means no phase
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

func TestReconcile_PausedAnnotationOnOwnedCRSkipsAdoption(t *testing.T) {
	// Production path: the infra CR is owned by a CAPI Machine, which
	// is owned by a Cluster. Operator annotates just the infra CR.
	// Mirrors the recovery recipe in AGENTS.md.
	cluster := &clusterv1.Cluster{
		ObjectMeta: metav1.ObjectMeta{Name: "c1", Namespace: "ns"},
		Status:     clusterv1.ClusterStatus{InfrastructureReady: true},
	}
	ownerMachine := &clusterv1.Machine{
		ObjectMeta: metav1.ObjectMeta{Name: "m1", Namespace: "ns"},
		Spec:       clusterv1.MachineSpec{ClusterName: "c1"},
	}
	machine := &infrav1.ScalewayAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "m1",
			Namespace: "ns",
			Annotations: map[string]string{
				"cluster.x-k8s.io/paused": "true",
			},
			OwnerReferences: []metav1.OwnerReference{{
				APIVersion: clusterv1.GroupVersion.String(),
				Kind:       "Machine",
				Name:       ownerMachine.Name,
				UID:        "owner-uid",
			}},
		},
		Spec: infrav1.ScalewayAppleSiliconMachineSpec{
			AdoptPoolPrefix: "tuist-pool-",
			Type:            "M2-L",
			Zone:            "fr-par-1",
			OS:              "macos-tahoe-26.3",
		},
	}
	r := newReconciler(t, cluster, ownerMachine, machine)
	result, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{Name: "m1", Namespace: "ns"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.RequeueAfter != 0 || result.Requeue {
		t.Fatalf("paused owned CR must not be requeued; got %+v", result)
	}
	got := &infrav1.ScalewayAppleSiliconMachine{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "m1", Namespace: "ns"}, got); err != nil {
		t.Fatalf("get machine: %v", err)
	}
	if got.Status.Phase != "" {
		t.Fatalf("paused owned CR phase should be untouched; got %q", got.Status.Phase)
	}
}

func TestReconcile_PausedAnnotationDoesNotBlockDelete(t *testing.T) {
	// Pause gate must NOT interpose between DeletionTimestamp and
	// reconcileDelete — otherwise the cleanup recipe in AGENTS.md
	// can't proceed (operator annotates first, clears status, deletes;
	// the delete has to drain through to finalizer removal). When
	// status.ServerID is empty, reconcileDelete skips the Scaleway
	// release (Stage 1) and runs through Stages 2-5 against the fake
	// client — every Delete tolerates IsNotFound, so the CR's
	// finalizer drops and the object disappears.
	deletionTime := metav1.Now()
	machine := &infrav1.ScalewayAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{
			Name:              "m1",
			Namespace:         "ns",
			DeletionTimestamp: &deletionTime,
			Finalizers:        []string{MachineFinalizer},
			Annotations: map[string]string{
				"cluster.x-k8s.io/paused": "true",
			},
		},
		Status: infrav1.ScalewayAppleSiliconMachineStatus{
			// serverID empty: reconcileDelete will skip the Scaleway
			// release stage that needs a non-nil ScalewayClient.
			ServerID: "",
		},
	}
	r := newReconciler(t, machine)
	// Intentionally leaving r.ScalewayClient nil — Stage 1 must be
	// skipped because ServerID is empty, so we should never touch it.

	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{Name: "m1", Namespace: "ns"},
	}); err != nil {
		t.Fatalf("unexpected reconcile error: %v", err)
	}

	// Finalizer removed → object fully gone from the fake client.
	got := &infrav1.ScalewayAppleSiliconMachine{}
	err := r.Get(context.Background(), types.NamespacedName{Name: "m1", Namespace: "ns"}, got)
	if err == nil {
		t.Fatalf("expected machine to be gone after delete reconcile; got finalizers=%v phase=%q",
			got.Finalizers, got.Status.Phase)
	}
	if !apierrors.IsNotFound(err) {
		t.Fatalf("expected NotFound, got: %v", err)
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

// --- reconcileDelete -------------------------------------------------------
//
// End-to-end check that reconcileDelete always returns the Scaleway
// server to the pool via ReleaseToPool. Uses a real *scaleway.Client
// backed by a minimal in-memory API so the recorded side-effects
// (rename + reinstall) are visible.

// scalewayAPIStub is a tiny implementation of
// scaleway.AppleSiliconAPI sufficient for the deletion path. Every
// method we don't care about returns an error so an unexpected call
// is loud in test output rather than silently doing nothing.
type scalewayAPIStub struct {
	servers        []*applesilicon.Server
	updateCalls    int
	updatedNames   []string
	reinstalledIDs []string
	reinstallCalls int
	rebootedIDs    []string
	rebootCalls    int
	rebootError    error
}

func (f *scalewayAPIStub) ListServers(*applesilicon.ListServersRequest, ...scw.RequestOption) (*applesilicon.ListServersResponse, error) {
	return nil, errors.New("ListServers not implemented in stub")
}

func (f *scalewayAPIStub) GetServer(req *applesilicon.GetServerRequest, _ ...scw.RequestOption) (*applesilicon.Server, error) {
	for _, s := range f.servers {
		if s.ID == req.ServerID {
			return s, nil
		}
	}
	return nil, errors.New("not found")
}

func (f *scalewayAPIStub) UpdateServer(req *applesilicon.UpdateServerRequest, _ ...scw.RequestOption) (*applesilicon.Server, error) {
	f.updateCalls++
	for _, s := range f.servers {
		if s.ID == req.ServerID {
			if req.Name != nil {
				s.Name = *req.Name
				f.updatedNames = append(f.updatedNames, *req.Name)
			}
			return s, nil
		}
	}
	return nil, errors.New("not found")
}

func (f *scalewayAPIStub) ReinstallServer(req *applesilicon.ReinstallServerRequest, _ ...scw.RequestOption) (*applesilicon.Server, error) {
	f.reinstallCalls++
	for _, s := range f.servers {
		if s.ID == req.ServerID {
			f.reinstalledIDs = append(f.reinstalledIDs, s.ID)
			return s, nil
		}
	}
	return nil, errors.New("not found")
}

func (f *scalewayAPIStub) RebootServer(req *applesilicon.RebootServerRequest, _ ...scw.RequestOption) (*applesilicon.Server, error) {
	f.rebootCalls++
	if f.rebootError != nil {
		return nil, f.rebootError
	}
	for _, s := range f.servers {
		if s.ID == req.ServerID {
			f.rebootedIDs = append(f.rebootedIDs, s.ID)
			return s, nil
		}
	}
	return nil, errors.New("not found")
}

func TestReconcileDelete_ReleasesToPool(t *testing.T) {
	api := &scalewayAPIStub{
		servers: []*applesilicon.Server{{ID: "srv-1", Name: "tuist-tuist-macos-fleet-0"}},
	}
	machine := &infrav1.ScalewayAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{
			Name:       "macos-fleet-0",
			Namespace:  "ns",
			Finalizers: []string{MachineFinalizer},
		},
		Spec: infrav1.ScalewayAppleSiliconMachineSpec{
			AdoptPoolPrefix: "tuist-pool-",
			Zone:            "fr-par-1",
		},
		Status: infrav1.ScalewayAppleSiliconMachineStatus{ServerID: "srv-1"},
	}
	r := newReconciler(t)
	r.ScalewayClient = &scaleway.Client{API: api}

	if _, err := r.reconcileDelete(context.Background(), machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}

	if got := api.reinstalledIDs; len(got) != 1 || got[0] != "srv-1" {
		t.Fatalf("expected ReinstallServer call for srv-1, got %v", got)
	}
	if got := api.updatedNames; len(got) != 1 || !startsWith(got[0], "tuist-pool-") {
		t.Fatalf("expected rename into the pool namespace, got %v", got)
	}
	if machine.Status.ServerID != "" {
		t.Fatalf("Status.ServerID should be cleared after release, got %q", machine.Status.ServerID)
	}
}

// TestReconcileDelete_LegacyCRWithoutPrefixSkipsRelease covers the
// compatibility path for CRs created under the older chart that only
// rendered `adoptPoolPrefix` when the value was non-empty. Those
// objects can't safely ReleaseToPool (the client refuses an empty
// prefix to avoid orphaning hosts outside the pool namespace), so
// the controller skips Stage 1 and proceeds to the rest of the
// teardown. Without this fallthrough, deleting a legacy CR would
// loop forever and block fleet shrinkage.
func TestReconcileDelete_LegacyCRWithoutPrefixSkipsRelease(t *testing.T) {
	api := &scalewayAPIStub{
		servers: []*applesilicon.Server{{ID: "srv-legacy", Name: "tuist-tuist-macos-fleet-legacy"}},
	}
	machine := &infrav1.ScalewayAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{
			Name:       "macos-fleet-legacy",
			Namespace:  "ns",
			Finalizers: []string{MachineFinalizer},
		},
		Spec: infrav1.ScalewayAppleSiliconMachineSpec{
			// Empty AdoptPoolPrefix — predates the required-prefix contract.
			Zone: "fr-par-1",
		},
		Status: infrav1.ScalewayAppleSiliconMachineStatus{ServerID: "srv-legacy"},
	}
	r := newReconciler(t)
	r.ScalewayClient = &scaleway.Client{API: api}

	result, err := r.reconcileDelete(context.Background(), machine)
	if err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if result.RequeueAfter != 0 || result.Requeue {
		t.Fatalf("legacy CR delete must not requeue; got %+v", result)
	}
	if len(api.reinstalledIDs) != 0 {
		t.Fatalf("legacy CR must NOT trigger Scaleway release; got reinstalls for %v", api.reinstalledIDs)
	}
	if len(api.updatedNames) != 0 {
		t.Fatalf("legacy CR must NOT rename the server; got %v", api.updatedNames)
	}
	if machine.Status.ServerID != "" {
		t.Fatalf("Status.ServerID should be cleared even when release is skipped, got %q", machine.Status.ServerID)
	}
}

func startsWith(s, prefix string) bool {
	return len(s) >= len(prefix) && s[:len(prefix)] == prefix
}

// --- handleBootstrapFailure ------------------------------------------------
//
// Tiered host recovery contract:
//   - Every call increments BootstrapAttempts and flips the
//     Bootstrapped condition to False with reason BootstrapFailed.
//   - At rebootAfter the controller asks Scaleway to reboot once
//     (gated on BootstrapRebootIssued).
//   - At maxAttempts the controller releases the host to the pool;
//     the counter + reboot flag reset because they describe the
//     now-discarded host.
//   - Scaleway API errors at either tier are non-fatal — the
//     machine stays in the failed state and the next call retries.

// recoveryStub is the smallest in-memory bootstrapRecoveryClient
// sufficient to drive the controller helper. It records every call so
// tests can assert on the exact API surface the recovery code
// triggered, and lets each method's first call inject an error.
type recoveryStub struct {
	rebootCalls   []recoveryCall
	rebootErr     error
	releaseCalls  []recoveryReleaseCall
	releaseErr    error
}

type recoveryCall struct {
	id   string
	zone string
}

type recoveryReleaseCall struct {
	id         string
	zone       string
	poolPrefix string
}

func (s *recoveryStub) RebootServer(_ context.Context, id, zone string) error {
	s.rebootCalls = append(s.rebootCalls, recoveryCall{id: id, zone: zone})
	if s.rebootErr != nil {
		return s.rebootErr
	}
	return nil
}

func (s *recoveryStub) ReleaseToPool(_ context.Context, id, zone, poolPrefix string) error {
	s.releaseCalls = append(s.releaseCalls, recoveryReleaseCall{id: id, zone: zone, poolPrefix: poolPrefix})
	if s.releaseErr != nil {
		return s.releaseErr
	}
	return nil
}

func newBootstrapFailureMachine(serverID, poolPrefix string) *infrav1.ScalewayAppleSiliconMachine {
	return &infrav1.ScalewayAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{Name: "machine-x", Namespace: "ns"},
		Spec: infrav1.ScalewayAppleSiliconMachineSpec{
			AdoptPoolPrefix: poolPrefix,
			Zone:            "fr-par-1",
		},
		Status: infrav1.ScalewayAppleSiliconMachineStatus{ServerID: serverID},
	}
}

func TestHandleBootstrapFailure_IncrementsAttempts(t *testing.T) {
	machine := newBootstrapFailureMachine("srv-1", "tuist-pool-")
	stub := &recoveryStub{}
	res := handleBootstrapFailure(context.Background(), machine, errors.New("ssh wedged"), stub, fakeRecorder(), logr.Discard(), 3, 8)

	if machine.Status.BootstrapAttempts != 1 {
		t.Fatalf("expected attempts=1, got %d", machine.Status.BootstrapAttempts)
	}
	if !conditions.IsFalse(machine, BootstrappedCondition) {
		t.Fatalf("expected Bootstrapped condition False")
	}
	if res.RequeueAfter != 60*time.Second {
		t.Fatalf("expected 60s requeue, got %v", res.RequeueAfter)
	}
	if len(stub.rebootCalls)+len(stub.releaseCalls) != 0 {
		t.Fatalf("first failure must not call Reboot or Release; got %+v / %+v", stub.rebootCalls, stub.releaseCalls)
	}
}

func TestHandleBootstrapFailure_RebootsAtThresholdOnce(t *testing.T) {
	// At rebootAfter the controller fires RebootServer once and
	// marks the attempt. Subsequent failures (gated on the issued
	// flag) must not re-fire the reboot — that would extend any
	// recovery window we just opened.
	machine := newBootstrapFailureMachine("srv-1", "tuist-pool-")
	machine.Status.BootstrapAttempts = 2 // next call lands at 3
	stub := &recoveryStub{}

	res := handleBootstrapFailure(context.Background(), machine, errors.New("sudo locked"), stub, fakeRecorder(), logr.Discard(), 3, 8)
	if res.RequeueAfter != 60*time.Second {
		t.Fatalf("expected 60s requeue, got %v", res.RequeueAfter)
	}
	if len(stub.rebootCalls) != 1 {
		t.Fatalf("expected one reboot at threshold, got %d", len(stub.rebootCalls))
	}
	if stub.rebootCalls[0] != (recoveryCall{id: "srv-1", zone: "fr-par-1"}) {
		t.Fatalf("unexpected reboot call shape: %+v", stub.rebootCalls[0])
	}
	if !machine.Status.BootstrapRebootIssued {
		t.Fatalf("Status.BootstrapRebootIssued must flip true after a successful reboot")
	}

	// Drive attempts past the threshold without crossing maxAttempts.
	// The reboot must not fire again because BootstrapRebootIssued is set.
	res = handleBootstrapFailure(context.Background(), machine, errors.New("still wedged"), stub, fakeRecorder(), logr.Discard(), 3, 8)
	if len(stub.rebootCalls) != 1 {
		t.Fatalf("reboot must be one-shot per host; got %d calls", len(stub.rebootCalls))
	}
	if machine.Status.BootstrapAttempts != 4 {
		t.Fatalf("expected attempts=4 after post-reboot retry, got %d", machine.Status.BootstrapAttempts)
	}
	if res.RequeueAfter != 60*time.Second {
		t.Fatalf("expected 60s requeue on post-reboot retry, got %v", res.RequeueAfter)
	}
}

func TestHandleBootstrapFailure_ReleasesToPoolAtMax(t *testing.T) {
	machine := newBootstrapFailureMachine("srv-1", "tuist-pool-")
	machine.Status.BootstrapAttempts = 7 // next call lands at 8 = maxAttempts
	machine.Status.BootstrapRebootIssued = true // assume reboot already tried earlier
	stub := &recoveryStub{}

	handleBootstrapFailure(context.Background(), machine, errors.New("unrecoverable"), stub, fakeRecorder(), logr.Discard(), 3, 8)

	if len(stub.releaseCalls) != 1 {
		t.Fatalf("expected one release call at max attempts, got %d", len(stub.releaseCalls))
	}
	if stub.releaseCalls[0] != (recoveryReleaseCall{id: "srv-1", zone: "fr-par-1", poolPrefix: "tuist-pool-"}) {
		t.Fatalf("unexpected release call shape: %+v", stub.releaseCalls[0])
	}
	if machine.Status.ServerID != "" {
		t.Fatalf("Status.ServerID must clear after release; got %q", machine.Status.ServerID)
	}
	if machine.Status.BootstrapAttempts != 0 || machine.Status.BootstrapRebootIssued {
		t.Fatalf("counters/flags must reset after release; got attempts=%d issued=%v",
			machine.Status.BootstrapAttempts, machine.Status.BootstrapRebootIssued)
	}
}

func TestHandleBootstrapFailure_ReleaseAPIErrorKeepsState(t *testing.T) {
	// Scaleway 5xx / network blip at release time: stay in the
	// failed state so the next reconcile retries the release. We
	// must NOT clear ServerID or the counter — that would let the
	// adoption stage try to claim a new host while the old one is
	// still wedged in our account.
	machine := newBootstrapFailureMachine("srv-1", "tuist-pool-")
	machine.Status.BootstrapAttempts = 7
	stub := &recoveryStub{releaseErr: errors.New("scaleway 503")}

	handleBootstrapFailure(context.Background(), machine, errors.New("unrecoverable"), stub, fakeRecorder(), logr.Discard(), 3, 8)

	if machine.Status.ServerID != "srv-1" {
		t.Fatalf("ServerID must persist when release fails; got %q", machine.Status.ServerID)
	}
	if machine.Status.BootstrapAttempts != 8 {
		t.Fatalf("attempts must still increment when release fails; got %d", machine.Status.BootstrapAttempts)
	}
}

func TestHandleBootstrapFailure_RebootAPIErrorDoesNotConsumeOneShot(t *testing.T) {
	// If RebootServer returns an error, BootstrapRebootIssued must
	// stay false — otherwise the one-shot guard would consume the
	// reboot tier on a Scaleway 5xx without actually rebooting,
	// and the controller would never retry the cheap recovery.
	machine := newBootstrapFailureMachine("srv-1", "tuist-pool-")
	machine.Status.BootstrapAttempts = 2
	stub := &recoveryStub{rebootErr: errors.New("scaleway 503")}

	handleBootstrapFailure(context.Background(), machine, errors.New("ssh wedged"), stub, fakeRecorder(), logr.Discard(), 3, 8)

	if len(stub.rebootCalls) != 1 {
		t.Fatalf("expected one reboot attempt despite error, got %d", len(stub.rebootCalls))
	}
	if machine.Status.BootstrapRebootIssued {
		t.Fatalf("BootstrapRebootIssued must stay false on RebootServer error to preserve the one-shot retry")
	}
}

func TestHandleBootstrapFailure_LegacyCRWithoutPoolPrefixNeverReleases(t *testing.T) {
	// Legacy CRs adopted under the old (no-prefix) chart contract
	// can't be safely returned to the pool — the client refuses an
	// empty prefix to avoid orphaning hosts outside the pool
	// namespace. Cap behaviour: stay in the failed state, never
	// trigger release. (Operator can clear FailureReason + ServerID
	// out-of-band to recover.)
	machine := newBootstrapFailureMachine("srv-legacy", "")
	machine.Status.BootstrapAttempts = 7

	stub := &recoveryStub{}
	handleBootstrapFailure(context.Background(), machine, errors.New("unrecoverable"), stub, fakeRecorder(), logr.Discard(), 3, 8)

	if len(stub.releaseCalls) != 0 {
		t.Fatalf("legacy CR (no pool prefix) must not trigger release; got %+v", stub.releaseCalls)
	}
	if machine.Status.ServerID == "" {
		t.Fatalf("legacy CR ServerID must persist; release path was bypassed")
	}
}

func TestHandleBootstrapFailure_DisabledThresholdsSkipBothTiers(t *testing.T) {
	// Setting either threshold to 0 disables that tier. Pure-retry
	// mode (both 0) is the operator escape hatch when fleet-wide
	// disruption shouldn't be automated.
	machine := newBootstrapFailureMachine("srv-1", "tuist-pool-")
	machine.Status.BootstrapAttempts = 100
	stub := &recoveryStub{}

	handleBootstrapFailure(context.Background(), machine, errors.New("boom"), stub, fakeRecorder(), logr.Discard(), 0, 0)

	if len(stub.rebootCalls) != 0 || len(stub.releaseCalls) != 0 {
		t.Fatalf("zero thresholds must skip both tiers; got reboots=%+v releases=%+v",
			stub.rebootCalls, stub.releaseCalls)
	}
}
