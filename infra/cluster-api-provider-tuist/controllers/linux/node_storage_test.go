package linux

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

// When a bare-metal fleet node is reprovisioned, deleteNodeLocalPVCs must reap
// only the PVCs bound to node-local PVs pinned to THAT node's hostname, leaving
// volumes on other nodes and network volumes (no hostname affinity) untouched.
func TestDeleteNodeLocalPVCs(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	const (
		deadNode = "tuist-tuist-kura-fleet-old-aaaaa"
		liveNode = "tuist-tuist-kura-fleet-new-bbbbb"
	)

	hostPinnedPV := func(name, hostname, claimName string) *corev1.PersistentVolume {
		return &corev1.PersistentVolume{
			ObjectMeta: metav1.ObjectMeta{Name: name},
			Spec: corev1.PersistentVolumeSpec{
				ClaimRef: &corev1.ObjectReference{Kind: "PersistentVolumeClaim", Namespace: "kura", Name: claimName},
				NodeAffinity: &corev1.VolumeNodeAffinity{Required: &corev1.NodeSelector{
					NodeSelectorTerms: []corev1.NodeSelectorTerm{{MatchExpressions: []corev1.NodeSelectorRequirement{{
						Key: corev1.LabelHostname, Operator: corev1.NodeSelectorOpIn, Values: []string{hostname},
					}}}},
				}},
			},
		}
	}
	pvc := func(name string) *corev1.PersistentVolumeClaim {
		return &corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Namespace: "kura", Name: name}}
	}
	networkPV := &corev1.PersistentVolume{
		ObjectMeta: metav1.ObjectMeta{Name: "pv-network"},
		Spec:       corev1.PersistentVolumeSpec{ClaimRef: &corev1.ObjectReference{Kind: "PersistentVolumeClaim", Namespace: "kura", Name: "data-net-0"}},
	}

	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(
		hostPinnedPV("pv-dead", deadNode, "data-dead-0"),
		hostPinnedPV("pv-live", liveNode, "data-live-0"),
		networkPV,
		pvc("data-dead-0"),
		pvc("data-live-0"),
		pvc("data-net-0"),
	).Build()

	if err := deleteNodeLocalPVCs(context.Background(), c, deadNode); err != nil {
		t.Fatal(err)
	}

	get := func(name string) error {
		return c.Get(context.Background(), types.NamespacedName{Namespace: "kura", Name: name}, &corev1.PersistentVolumeClaim{})
	}
	if err := get("data-dead-0"); !apierrors.IsNotFound(err) {
		t.Fatalf("PVC on the reprovisioned node must be deleted, got %v", err)
	}
	if err := get("data-live-0"); err != nil {
		t.Fatalf("PVC pinned to a different, live node must be kept, got %v", err)
	}
	if err := get("data-net-0"); err != nil {
		t.Fatalf("PVC on a network (non-node-local) volume must be kept, got %v", err)
	}
}

func TestPVPinnedToHostname(t *testing.T) {
	pinned := &corev1.PersistentVolume{Spec: corev1.PersistentVolumeSpec{
		NodeAffinity: &corev1.VolumeNodeAffinity{Required: &corev1.NodeSelector{
			NodeSelectorTerms: []corev1.NodeSelectorTerm{{MatchExpressions: []corev1.NodeSelectorRequirement{{
				Key: corev1.LabelHostname, Operator: corev1.NodeSelectorOpIn, Values: []string{"node-a"},
			}}}},
		}},
	}}
	if !pvPinnedToHostname(pinned, "node-a") {
		t.Fatal("expected a match for the pinned hostname")
	}
	if pvPinnedToHostname(pinned, "node-b") {
		t.Fatal("did not expect a match for a different hostname")
	}
	if pvPinnedToHostname(&corev1.PersistentVolume{}, "node-a") {
		t.Fatal("a PV without node affinity must never match")
	}
}
