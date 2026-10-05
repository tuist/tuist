package macos

import (
	"context"
	"testing"

	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/event"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// staleCache answers reads of the RackPDU with the object as it was before a
// reconcile's status landed, as the manager's informer can right after it.
type staleCache struct {
	client.Client
	pdu *infrav1.RackPDU
}

// Get serves the stale RackPDU once, to the reconcile's first read.
func (s *staleCache) Get(ctx context.Context, key client.ObjectKey, obj client.Object, opts ...client.GetOption) error {
	if p, ok := obj.(*infrav1.RackPDU); ok && s.pdu != nil && key.Name == s.pdu.Name {
		s.pdu.DeepCopyInto(p)
		s.pdu = nil
		return nil
	}
	return s.Client.Get(ctx, key, obj, opts...)
}

func adminLogins(h *pduHarness) int {
	h.card.Mu.Lock()
	defer h.card.Mu.Unlock()
	n := 0
	for _, who := range h.card.Logins {
		if who == "admin" {
			n++
		}
	}
	return n
}

// One generation is one adoption pass, even when the next reconcile reads a
// cache that has not seen the first one's status yet.
func TestRackPDUAdoptsOncePerGeneration(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	before := h.pdu()
	real := h.r.Client
	h.r.APIReader = real

	h.reconcile()
	h.r.Client = &staleCache{Client: real, pdu: before}
	h.reconcile()

	if n := h.eventsMatching("LoggedIn"); n != 1 {
		t.Fatalf("%d administrator logins for one generation, want 1", n)
	}
	if n := h.eventsMatching("Converged"); n != 1 {
		t.Fatalf("%d Converged events for one generation, want 1: %v", n, h.events)
	}
}

// A status write does not wake the reconciler: only a new generation or an
// annotation does.
func TestRackPDUIgnoresItsOwnStatusWrites(t *testing.T) {
	p := rackPDUPredicate()
	old := rackPDU()
	statusOnly := old.DeepCopy()
	statusOnly.Status.Adopted = true
	statusOnly.ResourceVersion = "2"
	if p.Update(event.UpdateEvent{ObjectOld: old, ObjectNew: statusOnly}) {
		t.Fatal("a status write woke the reconciler")
	}
	newGeneration := old.DeepCopy()
	newGeneration.Generation = 2
	if !p.Update(event.UpdateEvent{ObjectOld: old, ObjectNew: newGeneration}) {
		t.Fatal("a new generation did not wake the reconciler")
	}
	annotated := old.DeepCopy()
	annotated.Annotations = map[string]string{AcceptCertificateAnnotation: "AB"}
	if !p.Update(event.UpdateEvent{ObjectOld: old, ObjectNew: annotated}) {
		t.Fatal("the accept-certificate annotation did not wake the reconciler")
	}
}
