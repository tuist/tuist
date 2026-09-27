package macos

import (
	"context"
	"strings"
	"testing"

	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// A PDU the controller no longer manages is not one power goes through.
func TestRackPDUMadeStandaloneIsNotReady(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()
	h.assertAdopted()

	pdu := h.pdu()
	pdu.Spec.ManagedBy = infrav1.RackPDUManagedByStandalone
	if err := h.r.Update(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}
	h.reconcile()

	cond := conditions.Get(h.pdu(), clusterv1.ReadyCondition)
	if cond == nil || cond.Status == "True" || cond.Reason != "Standalone" {
		t.Fatalf("Ready = %+v, want False/Standalone", cond)
	}
}

// A host refuses power through a standalone PDU even while its status still
// says Ready.
func TestPowerIsRefusedThroughAStandaloneRackPDU(t *testing.T) {
	driver := &stubPowerDriver{on: true}
	host := pduHost("mini-01")
	host.Annotations = map[string]string{PowerActionAnnotation: "off", PowerActionForceAnnotation: "true"}
	pdu := readyPDU(true)
	pdu.Spec.ManagedBy = infrav1.RackPDUManagedByStandalone
	r := newRackHostReconciler(t, nil, host, pdu, pduCredentials())
	r.Power = eatonRegistry(driver)

	reconcileHost(t, r, "mini-01")

	cond := conditionOf(readHost(t, r, "mini-01"), PowerReachableCondition)
	if cond == nil || cond.Reason != "PDUNotReady" || !strings.Contains(cond.Message, "standalone") {
		t.Fatalf("PowerReachable = %+v, want PDUNotReady naming standalone", cond)
	}
	if calls := driver.recorded(); len(calls) != 0 {
		t.Fatalf("switched an outlet of a standalone PDU: %v", calls)
	}
}
