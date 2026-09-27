package macos

import (
	"context"
	"testing"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// A PDU the controller stops managing, or that is deleted, gets its session
// on the card logged out, so the card's one session for the account is free.
func TestRackPDUMadeStandaloneLogsTheControllerOut(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()
	if n := h.card.OpenSessions(); n != 1 {
		t.Fatalf("%d sessions after adoption, want the controller's", n)
	}
	pdu := h.pdu()
	pdu.Spec.ManagedBy = infrav1.RackPDUManagedByStandalone
	if err := h.r.Update(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}

	h.reconcile()

	if n := h.card.OpenSessions(); n != 0 {
		t.Fatalf("%d sessions left open on a standalone PDU", n)
	}
}

func TestRackPDUDeletedLogsTheControllerOut(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()
	h.card.Mu.Lock()
	logouts := h.card.Logouts
	h.card.Mu.Unlock()

	if err := h.r.Delete(context.Background(), h.pdu()); err != nil {
		t.Fatal(err)
	}
	h.reconcile()

	if n := h.card.OpenSessions(); n != 0 {
		t.Fatalf("%d sessions left open for a deleted PDU", n)
	}
	h.card.Mu.Lock()
	got := h.card.Logouts
	h.card.Mu.Unlock()
	if got != logouts+1 {
		t.Fatalf("logouts = %d, want %d", got, logouts+1)
	}
	err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "ber1-pdu-b"}, &infrav1.RackPDU{})
	if !apierrors.IsNotFound(err) {
		t.Fatalf("RackPDU after delete: %v", err)
	}
}
