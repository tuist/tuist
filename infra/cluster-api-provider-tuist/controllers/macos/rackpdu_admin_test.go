package macos

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
)

// A new generation of an adopted PDU whose administrator cannot log in (a
// person holds the administrator's one session, or changed its password)
// does not converge, and says so on Converged, but the PDU stays Ready while
// the controller's account works, so no host loses its power.
func TestAnAdoptedRackPDUKeepsPowerWhenTheAdministratorCannotLogIn(t *testing.T) {
	for name, tc := range map[string]struct {
		block  func(*eatontest.Card)
		reason string
	}{
		"busy": {func(c *eatontest.Card) {
			c.Mu.Lock()
			c.ForeignSessions["admin"] = true
			c.Mu.Unlock()
		}, "AdminSessionBusy"},
		"refused": {func(c *eatontest.Card) { setAccountPassword(c, "admin", "Somebody-else2") }, "AdminLoginRefused"},
	} {
		t.Run(name, func(t *testing.T) {
			h := newPDUHarness(t, rackPDU())
			h.reconcile()
			h.assertAdopted()
			tc.block(h.card)
			pdu := h.pdu()
			pdu.Spec.Chain, pdu.Generation = "ber1-ats-2", 2
			if err := h.r.Update(context.Background(), pdu); err != nil {
				t.Fatal(err)
			}

			for range 2 {
				h.reconcile()

				pdu = h.pdu()
				if ready := conditions.Get(pdu, clusterv1.ReadyCondition); ready == nil || ready.Status != corev1.ConditionTrue {
					t.Fatalf("Ready = %+v, want True while the controller's account works", ready)
				}
				converged := conditions.Get(pdu, RackPDUConvergedCondition)
				if converged == nil || converged.Status != corev1.ConditionFalse || converged.Reason != tc.reason {
					t.Fatalf("Converged = %+v, want False/%s", converged, tc.reason)
				}
				if !pdu.Status.Adopted || pdu.Status.ObservedGeneration != 1 {
					t.Fatalf("adopted %v at generation %d, want still adopted at 1", pdu.Status.Adopted, pdu.Status.ObservedGeneration)
				}
				if _, _, err := rackHostOutlet(context.Background(), h.r.Client, h.r.Power, "", egressConfig{}, pduHost("mini-01")); err != nil {
					t.Fatalf("host power refused: %v", err)
				}
			}
		})
	}
}

// The transfer switch already keeps observing an adopted card whose
// administrator cannot log in for a new generation.
func TestAnAdoptedRackATSKeepsObservingWhenTheAdministratorCannotLogIn(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	h.assertAdopted(1)
	h.card.Mu.Lock()
	h.card.ForeignSessions["admin"] = true
	h.card.Mu.Unlock()
	h.update(func(a *infrav1.RackATS) { a.Spec.PreferredSource, a.Generation = 2, 2 })

	h.reconcile()

	ats := h.ats()
	if !conditions.IsTrue(ats, clusterv1.ReadyCondition) || h.gauge("observed") != 1 {
		t.Fatalf("Ready = %+v, want the switch still observed", conditions.Get(ats, clusterv1.ReadyCondition))
	}
	if cond := conditions.Get(ats, RackCardConvergedCondition); cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != "AdminSessionBusy" {
		t.Fatalf("Converged = %+v, want False/AdminSessionBusy", cond)
	}
}
