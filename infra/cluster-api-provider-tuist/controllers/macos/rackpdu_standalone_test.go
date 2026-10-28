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
	pdu.Spec.ManagedBy = infrav1.RackCardManagedByStandalone
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
	pdu.Spec.ManagedBy = infrav1.RackCardManagedByStandalone
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

// A standalone PDU is one the controller never contacts, as a planned PDU at a
// site that is not racked yet, so it has nothing to report: a Ready series of
// 0 would read as a PDU that cannot be observed. Its series go when an adopted
// PDU is made standalone, as a standalone RackATS has none.
func TestAStandaloneRackPDUHasNoMetrics(t *testing.T) {
	hasSeries := func() []string {
		var found []string
		for name, g := range map[string]interface {
			DeleteLabelValues(...string) bool
		}{"adopted": rackPDUAdoptedGauge, "ready": rackPDUReadyGauge, "drifted": rackPDUDriftedGauge, "certificate changed": rackPDUCertificateChangedGauge} {
			if g.DeleteLabelValues("ber1-pdu-b", "ber1") {
				found = append(found, name)
			}
		}
		return found
	}
	planned := func(p *infrav1.RackPDU) {
		p.Spec.ManagedBy = infrav1.RackCardManagedByStandalone
	}

	h := newPDUHarness(t, rackPDU(planned))
	h.reconcile()
	if found := hasSeries(); len(found) != 0 {
		t.Fatalf("a standalone PDU exports %v", found)
	}

	h = newPDUHarness(t, rackPDU())
	h.reconcile()
	pdu := h.pdu()
	pdu.Spec.ManagedBy = infrav1.RackCardManagedByStandalone
	if err := h.r.Update(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}
	h.reconcile()
	if found := hasSeries(); len(found) != 0 {
		t.Fatalf("a PDU made standalone keeps %v", found)
	}
}
