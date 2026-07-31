package controllers

import (
	"context"
	"fmt"
	"os"
	"reflect"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/yaml"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func TestAggregateBackfillInitialCycle(t *testing.T) {
	cases := []struct {
		name  string
		modes []string
		want  string
	}{
		{name: "no statuses", modes: nil, want: ""},
		{name: "all absent (pre-backfill pods)", modes: []string{"", ""}, want: ""},
		{name: "all complete", modes: []string{"complete", "complete"}, want: "complete"},
		{name: "pending outranks complete", modes: []string{"complete", "pending"}, want: "pending"},
		{name: "degraded outranks everything", modes: []string{"complete", "pending", "degraded"}, want: "degraded"},
		{name: "complete outranks absent (mixed rolling update)", modes: []string{"", "complete"}, want: "complete"},
		{name: "unknown mode outranks pending so the server holds", modes: []string{"pending", "later-vocabulary"}, want: "later-vocabulary"},
		{name: "degraded outranks unknown", modes: []string{"later-vocabulary", "degraded"}, want: "degraded"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			statuses := make([]runtimeStatus, 0, len(tc.modes))
			for _, mode := range tc.modes {
				statuses = append(statuses, runtimeStatus{BackfillInitialCycle: mode})
			}
			if got := aggregateBackfillInitialCycle(statuses); got != tc.want {
				t.Fatalf("expected %q, got %q", tc.want, got)
			}
		})
	}
}

func TestKuraInstanceReconcileSurfacesBackfillInitialCycle(t *testing.T) {
	ctx := context.Background()
	reconciler, req := newBackfillTestReconciler(t, "", fakeRuntimeStatusClient{
		statuses: map[string]runtimeStatus{
			"kura-tuist-eu-1-0": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2, BackfillInitialCycle: "pending"},
			"kura-tuist-eu-1-1": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2, BackfillInitialCycle: "complete"},
			"kura-tuist-eu-1-2": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
		},
	})

	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}
	assertBackfillInitialCycle(t, reconciler, req, "pending")

	// Background retries finished the cycle: the mode advances without a
	// pod restart, so a fresh probe must move the status forward.
	reconciler.RuntimeStatusClient = fakeRuntimeStatusClient{
		statuses: map[string]runtimeStatus{
			"kura-tuist-eu-1-0": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2, BackfillInitialCycle: "complete"},
			"kura-tuist-eu-1-1": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2, BackfillInitialCycle: "complete"},
			"kura-tuist-eu-1-2": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2, BackfillInitialCycle: "complete"},
		},
	}
	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}
	assertBackfillInitialCycle(t, reconciler, req, "complete")
}

func TestKuraInstanceReconcileClearsBackfillCycleWhenNoPodReportsIt(t *testing.T) {
	// A rollback to a pre-backfill image stops reporting the field; the
	// instance status must follow so the server applies today's semantics
	// instead of holding on a stale mode forever.
	ctx := context.Background()
	reconciler, req := newBackfillTestReconciler(t, "pending", fakeRuntimeStatusClient{
		statuses: map[string]runtimeStatus{
			"kura-tuist-eu-1-0": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
			"kura-tuist-eu-1-1": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
			"kura-tuist-eu-1-2": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
		},
	})

	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}
	assertBackfillInitialCycle(t, reconciler, req, "")
}

func TestKuraInstanceReconcileRetainsBackfillCycleWhenRuntimeStatusUnavailable(t *testing.T) {
	// A probe outage yields zero runtime statuses. Clearing the mode then
	// would make a backfilling target look pre-backfill to the server and
	// ungate promotion, so the last observed mode is retained.
	ctx := context.Background()
	reconciler, req := newBackfillTestReconciler(t, "pending", fakeRuntimeStatusClient{err: fmt.Errorf("status endpoint unreachable")})

	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}
	assertBackfillInitialCycle(t, reconciler, req, "pending")
}

func newBackfillTestReconciler(t *testing.T, initialCycle string, statusClient RuntimeStatusClient) (*KuraInstanceReconciler, ctrl.Request) {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:    "tuist",
			TenantID:         "tuist",
			Region:           "eu",
			Image:            "ghcr.io/tuist/kura:0.5.2",
			PublicHost:       "tuist-eu-1.kura.tuist.dev",
			StorageClassName: "hcloud-volumes",
		},
		Status: kurav1alpha1.KuraInstanceStatus{BackfillInitialCycle: initialCycle},
	}
	sharedSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: sharedSecretsName, Namespace: instance.Namespace, ResourceVersion: "1"},
	}
	client := fake.NewClientBuilder().WithScheme(scheme).WithStatusSubresource(instance, &corev1.Pod{}).WithObjects(
		instance,
		sharedSecret,
		kuraPod(instance.Name, instance.Namespace, 0, true),
		kuraPod(instance.Name, instance.Namespace, 1, true),
		kuraPod(instance.Name, instance.Namespace, 2, true),
	).Build()
	reconciler := &KuraInstanceReconciler{
		Client:              client,
		Scheme:              scheme,
		RuntimeStatusClient: statusClient,
	}
	req := ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}
	return reconciler, req
}

func assertBackfillInitialCycle(t *testing.T, r *KuraInstanceReconciler, req ctrl.Request, want string) {
	t.Helper()
	instance := &kurav1alpha1.KuraInstance{}
	if err := r.Get(context.Background(), req.NamespacedName, instance); err != nil {
		t.Fatal(err)
	}
	if instance.Status.BackfillInitialCycle != want {
		t.Fatalf("expected backfillInitialCycle %q, got %q", want, instance.Status.BackfillInitialCycle)
	}
}

// The controller has no envtest harness, so a real-apiserver schema
// round-trip is not testable here. This guards the pruning hazard the
// cheap way instead: every json field the controller can write into
// KuraInstanceStatus must be declared in the chart's CRD structural
// schema, or the apiserver silently drops it (which for
// backfillInitialCycle would silently ungate move promotion).
func TestCRDStatusSchemaDeclaresEveryStatusField(t *testing.T) {
	raw, err := os.ReadFile("../../helm/tuist/crds/kura.tuist.dev_kurainstances.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var crd map[string]interface{}
	if err := yaml.Unmarshal(raw, &crd); err != nil {
		t.Fatal(err)
	}

	properties := crdStatusProperties(t, crd)

	statusType := reflect.TypeOf(kurav1alpha1.KuraInstanceStatus{})
	for i := 0; i < statusType.NumField(); i++ {
		tag := statusType.Field(i).Tag.Get("json")
		name := strings.Split(tag, ",")[0]
		if name == "" || name == "-" {
			continue
		}
		if _, ok := properties[name]; !ok {
			t.Errorf("status field %q is missing from the CRD structural schema; the apiserver will prune it", name)
		}
	}
}

func crdStatusProperties(t *testing.T, crd map[string]interface{}) map[string]interface{} {
	t.Helper()
	spec, ok := crd["spec"].(map[string]interface{})
	if !ok {
		t.Fatal("CRD has no spec")
	}
	versions, ok := spec["versions"].([]interface{})
	if !ok || len(versions) == 0 {
		t.Fatal("CRD has no versions")
	}
	node, ok := versions[0].(map[string]interface{})
	if !ok {
		t.Fatal("CRD version is not a mapping")
	}
	for _, key := range []string{"schema", "openAPIV3Schema", "properties", "status", "properties"} {
		next, ok := node[key].(map[string]interface{})
		if !ok {
			t.Fatalf("CRD schema is missing %q", key)
		}
		node = next
	}
	return node
}
