package linux

import (
	"context"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

func claimScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatalf("add infrav1 to scheme: %v", err)
	}
	return scheme
}

func claimingMachine(ns, name, service string) *infrav1.OVHDedicatedMachine {
	m := &infrav1.OVHDedicatedMachine{
		ObjectMeta: metav1.ObjectMeta{Namespace: ns, Name: name, UID: types.UID(name)},
	}
	m.Status.ServiceName = service
	return m
}

// A claim is only durable once its status patch lands, and the informer cache
// lags that write. A sibling that reads through the cache therefore sees a box
// as free after it was claimed and adopts it too, bootstrapping one host twice
// and leaving two Nodes sharing a providerID, which wedges the CAPI node lookup
// for both Machines. The claim read must bypass the cache.
func TestClaimedServiceNamesReadsUncached(t *testing.T) {
	const ns = "tuist"
	scheme := claimScheme(t)

	self := claimingMachine(ns, "adopter", "")
	sibling := claimingMachine(ns, "sibling", "ns3048220.ip-51-255-75.eu")

	// The cached client is behind: it has not observed the sibling's claim yet.
	cached := fake.NewClientBuilder().WithScheme(scheme).WithObjects(self).Build()
	live := fake.NewClientBuilder().WithScheme(scheme).WithObjects(self, sibling).Build()

	r := &OVHDedicatedMachineReconciler{Client: cached, APIReader: live}

	claimed, err := r.claimedServiceNames(context.Background(), self)
	if err != nil {
		t.Fatalf("claimedServiceNames: %v", err)
	}
	if !claimed["ns3048220.ip-51-255-75.eu"] {
		t.Fatalf("claimedServiceNames = %v, want the sibling's claim; a cached read double-claims the box", claimed)
	}
}

// Without an APIReader wired the reconciler still has to exclude siblings
// rather than returning an empty set and adopting everything twice.
func TestClaimedServiceNamesFallsBackToClient(t *testing.T) {
	const ns = "tuist"
	scheme := claimScheme(t)

	self := claimingMachine(ns, "adopter", "")
	sibling := claimingMachine(ns, "sibling", "ns3049612.ip-51-255-75.eu")
	cl := fake.NewClientBuilder().WithScheme(scheme).WithObjects(self, sibling).Build()

	r := &OVHDedicatedMachineReconciler{Client: cl}

	claimed, err := r.claimedServiceNames(context.Background(), self)
	if err != nil {
		t.Fatalf("claimedServiceNames: %v", err)
	}
	if !claimed["ns3049612.ip-51-255-75.eu"] {
		t.Fatalf("claimedServiceNames = %v, want the sibling's claim", claimed)
	}
}
