package macos

import (
	"context"
	"strings"
	"testing"
	"time"

	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
)

func cardWrites(card *eatontest.Card) []string {
	card.Mu.Lock()
	defer card.Mu.Unlock()
	return append([]string(nil), card.Writes...)
}

// A RackATS pointed at a factory PDU card changes the card's administrator
// password at its first login, which the card forces before anything can ask
// it what it is. The RackATS reports the card as unsupported and names the
// Secret holding that password, and the RackPDU for the card then logs in
// with it and adopts the card.
func TestARackATSOnAPDUCardLeavesItAdoptableByTheRackPDU(t *testing.T) {
	ats := rackATS(func(a *infrav1.RackATS) { a.Spec.Address = "192.168.0.16" })
	h := newPDUHarness(t, rackPDU(), ats)
	previous := rackATSHost
	rackATSHost = func(*infrav1.RackATS) string { return h.card.URL() }
	t.Cleanup(func() { rackATSHost = previous })
	t.Cleanup(func() { forgetRackATSMetrics(testATS) })
	atsRecorder := record.NewFakeRecorder(100)
	atsReconciler := &RackATSReconciler{Client: h.r.Client, Scheme: h.r.Scheme, Recorder: atsRecorder, Power: h.r.Power, Timeout: 5 * time.Second, RootKeySecret: testRootKeyRef}

	if _, err := atsReconciler.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: testNamespace, Name: testATS}}); err != nil {
		t.Fatal(err)
	}
	got := &infrav1.RackATS{}
	if err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: testATS}, got); err != nil {
		t.Fatal(err)
	}
	cond := conditions.Get(got, RackCardAdoptedCondition)
	if cond == nil || cond.Reason != "UnsupportedCard" || !strings.Contains(cond.Message, testNamespace+"/"+testATS+"-credentials") {
		t.Fatalf("Adopted = %+v, want UnsupportedCard naming the Secret that holds the administrator password", cond)
	}
	if w := cardWrites(h.card); len(w) != 1 || w[0] != "password admin" {
		t.Fatalf("the RackATS wrote %v to a PDU card, want only the forced password change", w)
	}

	h.reconcile()

	h.assertAdopted()
	if h.eventsMatching(testATS+"-credentials") != 2 || h.eventsMatching("PasswordRotated") != 1 {
		t.Fatalf("events = %v, want the login and the rotation naming the Secret the administrator password came from", h.events)
	}
	if h.card.Account("admin").Password != pduPasswords().Admin {
		t.Fatal("the RackPDU did not move the card onto its derived administrator password")
	}
}

// The mirror: a RackPDU pointed at a factory transfer switch card.
func TestARackPDUOnAnATSCardLeavesItAdoptableByTheRackATS(t *testing.T) {
	pdu := rackPDU(func(p *infrav1.RackPDU) { p.Spec.Address = "192.168.0.14" })
	h := newATSHarness(t, rackATS(), pdu)
	previous := rackPDUHost
	rackPDUHost = func(*infrav1.RackPDU) string { return h.card.URL() }
	t.Cleanup(func() { rackPDUHost = previous })
	t.Cleanup(func() { forgetRackPDUMetrics("ber1-pdu-b") })
	pduReconciler := &RackPDUReconciler{Client: h.r.Client, Scheme: h.r.Scheme, Recorder: record.NewFakeRecorder(100), Power: h.r.Power, Timeout: 5 * time.Second, RootKeySecret: testRootKeyRef}

	if _, err := pduReconciler.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: testNamespace, Name: "ber1-pdu-b"}}); err != nil {
		t.Fatal(err)
	}
	got := &infrav1.RackPDU{}
	if err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "ber1-pdu-b"}, got); err != nil {
		t.Fatal(err)
	}
	cond := conditions.Get(got, RackCardAdoptedCondition)
	if cond == nil || cond.Reason != "UnsupportedCard" || !strings.Contains(cond.Message, `"ats"`) ||
		!strings.Contains(cond.Message, testNamespace+"/ber1-pdu-b-credentials") {
		t.Fatalf("Adopted = %+v, want UnsupportedCard saying it is an ats and naming the Secret", cond)
	}
	if conditions.IsTrue(got, clusterv1.ReadyCondition) {
		t.Fatal("a RackPDU on a transfer switch is Ready")
	}
	if w := cardWrites(h.card); len(w) != 1 || w[0] != "password admin" {
		t.Fatalf("the RackPDU wrote %v to a transfer switch card, want only the forced password change", w)
	}

	h.reconcile()

	h.assertAdopted(1)
	if !power.SameTLSFingerprint(string(h.secret().Data["tlsFingerprint"]), h.card.Fingerprint()) {
		t.Fatal("the RackATS did not pin the card")
	}
}

// Every credentials Secret carries its card's address, which is how another
// object's Secret for the same card is found.
func TestCardCredentialsSecretsCarryTheCardsAddress(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	if got := h.secret().Labels[rackCardAddressLabel]; got != "192.168.0.14" {
		t.Fatalf("%s = %q", rackCardAddressLabel, got)
	}
	h.update(func(a *infrav1.RackATS) { a.Spec.Address = "192.168.0.24" })
	h.reconcile()
	if got := h.secret().Labels[rackCardAddressLabel]; got != "192.168.0.24" {
		t.Fatalf("after the address moved, %s = %q", rackCardAddressLabel, got)
	}
}
