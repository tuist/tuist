package shared

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// Verify the externally-managed control-plane handshake: the SASC
// reconciler must flip its own Status.Ready=true AND mark the parent
// Cluster's ControlPlaneInitialized condition True. Without the
// latter, CAPI core's MachineSet controller refuses to create the
// per-Machine InfrastructureMachine (SASM), leaving Machines
// permanently orphaned with no Scaleway-side resource attached.
//
// The orphan state is impossible to self-heal from — the only
// recovery is `kubectl delete machine ...` — so guarding the patch
// behind a unit test is cheap insurance.
func TestSASCReconciler_MarksControlPlaneInitializedOnParentCluster(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatalf("add SASC scheme: %v", err)
	}
	if err := clusterv1.AddToScheme(scheme); err != nil {
		t.Fatalf("add cluster-api scheme: %v", err)
	}

	infraCluster := &infrav1.TuistCluster{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "tuist-tuist-capi",
			Namespace: "tuist-staging",
			OwnerReferences: []metav1.OwnerReference{
				{
					APIVersion: clusterv1.GroupVersion.String(),
					Kind:       "Cluster",
					Name:       "tuist-tuist-capi",
					UID:        "00000000-0000-0000-0000-000000000001",
				},
			},
		},
	}
	cluster := &clusterv1.Cluster{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "tuist-tuist-capi",
			Namespace: "tuist-staging",
			UID:       "00000000-0000-0000-0000-000000000001",
		},
		Spec: clusterv1.ClusterSpec{
			InfrastructureRef: &corev1.ObjectReference{
				APIVersion: infrav1.GroupVersion.String(),
				Kind:       "TuistCluster",
				Name:       "tuist-tuist-capi",
				Namespace:  "tuist-staging",
			},
		},
	}

	cl := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(infraCluster, cluster).
		WithStatusSubresource(infraCluster, cluster).
		Build()

	r := &TuistClusterReconciler{
		Client: cl,
		Scheme: scheme,
	}

	_, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{
			Namespace: "tuist-staging",
			Name:      "tuist-tuist-capi",
		},
	})
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := &infrav1.TuistCluster{}
	if err := cl.Get(context.Background(), types.NamespacedName{
		Namespace: "tuist-staging",
		Name:      "tuist-tuist-capi",
	}, got); err != nil {
		t.Fatalf("get SASC after reconcile: %v", err)
	}
	if !got.Status.Ready {
		t.Errorf("SASC.Status.Ready: got false, want true")
	}

	gotCluster := &clusterv1.Cluster{}
	if err := cl.Get(context.Background(), types.NamespacedName{
		Namespace: "tuist-staging",
		Name:      "tuist-tuist-capi",
	}, gotCluster); err != nil {
		t.Fatalf("get Cluster after reconcile: %v", err)
	}
	if !conditions.IsTrue(gotCluster, clusterv1.ControlPlaneInitializedCondition) {
		t.Errorf("Cluster.ControlPlaneInitialized: got false/unknown, want true. Conditions: %+v", gotCluster.Status.Conditions)
	}
}

// Without an owner Cluster yet (first reconcile races CAPI core
// stamping the OwnerRef), the reconciler should not error — it
// should just bail and wait for the next tick when the OwnerRef
// arrives. Guards against the reconciler returning errors in
// transient startup state.
func TestSASCReconciler_NoOwnerClusterYet_NoError(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatalf("add SASC scheme: %v", err)
	}
	if err := clusterv1.AddToScheme(scheme); err != nil {
		t.Fatalf("add cluster-api scheme: %v", err)
	}

	infraCluster := &infrav1.TuistCluster{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "tuist-tuist-capi",
			Namespace: "tuist-staging",
		},
	}

	cl := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(infraCluster).
		WithStatusSubresource(infraCluster).
		Build()

	r := &TuistClusterReconciler{
		Client: cl,
		Scheme: scheme,
	}

	_, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{
			Namespace: "tuist-staging",
			Name:      "tuist-tuist-capi",
		},
	})
	if err != nil {
		t.Fatalf("reconcile with no owner Cluster: got error, want nil-error: %v", err)
	}
	got := &infrav1.TuistCluster{}
	_ = cl.Get(context.Background(), types.NamespacedName{
		Namespace: "tuist-staging",
		Name:      "tuist-tuist-capi",
	}, got)
	if !got.Status.Ready {
		t.Errorf("SASC.Status.Ready: got false, want true (should run before the owner-cluster lookup)")
	}
}

// The Cluster→SASC watch mapper must map a Cluster whose
// InfrastructureRef points at a TuistCluster to a
// reconcile request for that SASC. Anything else (no
// InfrastructureRef, or a non-SASC kind) returns nil so the watch
// doesn't enqueue spurious work on every Cluster event in the
// namespace.
func TestClusterToInfraClusterMapper(t *testing.T) {
	r := &TuistClusterReconciler{}

	t.Run("SASC-backed Cluster enqueues that SASC", func(t *testing.T) {
		cluster := &clusterv1.Cluster{
			ObjectMeta: metav1.ObjectMeta{Name: "c1", Namespace: "ns"},
			Spec: clusterv1.ClusterSpec{
				InfrastructureRef: &corev1.ObjectReference{
					APIVersion: infrav1.GroupVersion.String(),
					Kind:       "TuistCluster",
					Name:       "sasc-1",
					Namespace:  "ns",
				},
			},
		}
		got := r.clusterToInfraCluster(context.Background(), cluster)
		if len(got) != 1 || got[0].Name != "sasc-1" || got[0].Namespace != "ns" {
			t.Fatalf("got %+v, want one request for ns/sasc-1", got)
		}
	})

	t.Run("Cluster without InfrastructureRef returns nil", func(t *testing.T) {
		cluster := &clusterv1.Cluster{
			ObjectMeta: metav1.ObjectMeta{Name: "c2", Namespace: "ns"},
		}
		if got := r.clusterToInfraCluster(context.Background(), cluster); got != nil {
			t.Fatalf("got %+v, want nil", got)
		}
	})

	t.Run("Cluster with non-SASC InfrastructureRef returns nil", func(t *testing.T) {
		cluster := &clusterv1.Cluster{
			ObjectMeta: metav1.ObjectMeta{Name: "c3", Namespace: "ns"},
			Spec: clusterv1.ClusterSpec{
				InfrastructureRef: &corev1.ObjectReference{
					Kind: "DockerCluster",
					Name: "other",
				},
			},
		}
		if got := r.clusterToInfraCluster(context.Background(), cluster); got != nil {
			t.Fatalf("got %+v, want nil", got)
		}
	})

	t.Run("non-Cluster object returns nil", func(t *testing.T) {
		got := r.clusterToInfraCluster(context.Background(), &corev1.Node{})
		if got != nil {
			t.Fatalf("got %+v, want nil", got)
		}
	})
}
