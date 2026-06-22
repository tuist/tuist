package linux

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
)

// A deleted Linux Machine must delete the Node its kubelet registered. The
// gone/wiped host can't deregister itself, and the foreign providerID means
// no CCM reaps it, so a lingering NotReady Node keeps its DaemonSet slot and
// wedges helm --wait gates (an orphaned kura-fleet Node blocked the
// observability rollout, which gates every staging deploy). reconcileDelete
// across the three Linux providers shares this path; the Dedibox controller
// stands in for all of them.
func TestDediboxReconcileDeleteRemovesRegisteredNode(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := rbacv1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	const machineName = "tuist-tuist-kura-dedibox-abc12-xyz34"
	machine := &infrav1.DediboxMachine{
		ObjectMeta: metav1.ObjectMeta{
			Name:       machineName,
			Namespace:  "tuist",
			Finalizers: []string{DediboxMachineFinalizer},
		},
	}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: machineName}}
	cl := fake.NewClientBuilder().WithScheme(scheme).WithObjects(machine, node).Build()

	r := &DediboxMachineReconciler{
		Client:             cl,
		CredentialsManager: &credentials.Manager{Client: cl, Namespace: "tuist"},
	}

	if _, err := r.reconcileDelete(context.Background(), machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}

	if err := cl.Get(context.Background(), types.NamespacedName{Name: machineName}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the registered Node to be deleted, got err=%v", err)
	}
}
