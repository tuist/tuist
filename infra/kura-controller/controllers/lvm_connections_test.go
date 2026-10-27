package controllers

import (
	"context"
	"fmt"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

type stubConnectionRetirer struct {
	ready bool
	err   error
}

func (s stubConnectionRetirer) Retire(_ context.Context, _ corev1.Pod, _ string, incarnation string, _ map[string][]byte) (bool, error) {
	if incarnation != "current-boot" {
		return false, fmt.Errorf("wrong process")
	}
	return s.ready, s.err
}
func TestThinMigrationRequiresConnectionRetirement(t *testing.T) {
	for _, tc := range []struct {
		name, incarnation   string
		ready, failed, want bool
	}{
		{name: "old runtime holds migration"},
		{name: "live connections hold migration", incarnation: "current-boot"},
		{name: "failure holds migration", incarnation: "current-boot", failed: true},
		{name: "empty old cohort permits migration", incarnation: "current-boot", ready: true, want: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newResizeHoldFixture(600)
			f.instance.Spec.StorageClassName = thinLocalStorageClass
			p := f.servingPod(0, "600m")
			p.Status.PodIP = "10.0.0.1"
			c := fake.NewClientBuilder().WithScheme(meshTestScheme(t)).WithObjects(&corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(f.instance), Namespace: f.instance.Namespace}}).Build()
			retire := stubConnectionRetirer{ready: tc.ready}
			if tc.failed {
				retire.err = fmt.Errorf("timeout")
			}
			r := &KuraInstanceReconciler{Client: c, RuntimeStatusClient: fakeRuntimeStatusClient{statuses: map[string]runtimeStatus{p.Name: {ConnectionIncarnation: tc.incarnation}}}, PublicConnectionRetirer: retire}
			ready, err := r.lvmConnectionsRetired(context.Background(), f.instance, p)
			if ready != tc.want {
				t.Fatalf("ready=%v want %v", ready, tc.want)
			}
			if tc.failed && err == nil {
				t.Fatal("lost retirement error")
			}
		})
	}
}
