package macos

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
)

func adminAttempts(card *eatontest.Card) int {
	card.Mu.Lock()
	defer card.Mu.Unlock()
	n := 0
	for _, who := range card.LoginAttemptsBy {
		if who == "admin" {
			n++
		}
	}
	return n
}

// A host's power path never dials a RackPDU that is being deleted, even while
// the cache still shows it Ready: its controller has just logged out of the
// card, and a new session would hold the account until the card's idle
// timeout.
func TestHostPowerDoesNotDialARackPDUBeingDeleted(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()
	h.assertAdopted()
	if err := h.r.Delete(context.Background(), h.pdu()); err != nil {
		t.Fatal(err)
	}
	deleting := h.pdu()
	if deleting.DeletionTimestamp.IsZero() || !conditions.IsTrue(deleting, clusterv1.ReadyCondition) {
		t.Fatalf("setup: want a Ready RackPDU being deleted, have %+v", deleting.ObjectMeta)
	}
	h.reconcile()
	if n := h.card.OpenSessions(); n != 0 {
		t.Fatalf("%d sessions after the delete-time logout", n)
	}
	h.card.Mu.Lock()
	logins := len(h.card.Logins)
	h.card.Mu.Unlock()

	driver, outlet, err := rackHostOutlet(context.Background(), &staleCache{Client: h.r.Client, pdu: deleting}, h.r.Power, "", egressConfig{}, pduHost("mini-01"))
	if err == nil {
		_, _ = driver.State(context.Background(), outlet)
	}

	var notReady *pduNotReadyError
	if !errors.As(err, &notReady) || !strings.Contains(err.Error(), "being deleted") {
		t.Fatalf("rackHostOutlet = %v, want the RackPDU refused as being deleted", err)
	}
	h.card.Mu.Lock()
	after := len(h.card.Logins)
	h.card.Mu.Unlock()
	if after != logins || h.card.OpenSessions() != 0 {
		t.Fatalf("logged in again after the RackPDU's logout: %d new logins, %d sessions", after-logins, h.card.OpenSessions())
	}
}

func markedSecret(name, password, fingerprint string, at time.Time) *corev1.Secret {
	s := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: testNamespace,
			Labels: map[string]string{rackCardAddressLabel: "192.168.0.14"}},
		Data: map[string][]byte{"admin-username": []byte("admin"), "admin-password": []byte(password)},
	}
	if fingerprint != "" {
		s.Annotations = map[string]string{
			rackCardAdminSetAnnotation:            at.UTC().Format(time.RFC3339),
			rackCardAdminSetCertificateAnnotation: fingerprint,
		}
	}
	return s
}

// Of the other Secrets for the card's address, only the one that most
// recently recorded setting the administrator password on a card presenting
// this certificate is tried, so a card that blocks an account after a few
// failures is not walked through every leftover Secret.
func TestTheAdministratorLoginTriesOneMarkedSiblingAtMost(t *testing.T) {
	now := time.Now()
	h := newATSHarness(t, rackATS())
	fingerprint := h.card.Fingerprint()
	other := strings.Repeat("AB:", 31) + "AB"
	stale := []*corev1.Secret{
		markedSecret("a-unmarked-credentials", "Unmarked-pass1", "", now),
		markedSecret("b-other-card-credentials", "Other-card-pass1", other, now.Add(time.Hour)),
		markedSecret("c-older-credentials", "Older-pass1", fingerprint, now.Add(-time.Hour)),
		markedSecret("d-right-credentials", "Right-pass1", fingerprint, now),
	}
	for _, s := range stale {
		if err := h.r.Create(context.Background(), s); err != nil {
			t.Fatal(err)
		}
	}
	h.card.Mu.Lock()
	h.card.Accounts["0"].Password, h.card.Accounts["0"].PasswordExpired = "Right-pass1", false
	h.card.Mu.Unlock()

	h.reconcile()

	h.assertAdopted(1)
	if n := adminAttempts(h.card); n != 2 {
		t.Fatalf("%d administrator login attempts, want its own password and the one marked sibling", n)
	}
	if h.eventsMatching("d-right-credentials") != 2 || h.eventsMatching("PasswordRotated") != 1 {
		t.Fatalf("events = %v, want the login and the rotation to name the Secret it took the password from", h.events)
	}
}

// A marked Secret whose card presented another certificate is not tried.
func TestTheAdministratorLoginSkipsAMarkForAnotherCertificate(t *testing.T) {
	h := newATSHarness(t, rackATS())
	other := strings.Repeat("AB:", 31) + "AB"
	if err := h.r.Create(context.Background(), markedSecret("stale-credentials", "Stale-pass1", other, time.Now())); err != nil {
		t.Fatal(err)
	}

	h.reconcile()

	h.assertAdopted(1)
	if n := adminAttempts(h.card); n != 2 {
		t.Fatalf("%d administrator login attempts, want its own password and the factory login only", n)
	}
}

// Setting the administrator password at the forced first-login change is
// recorded on the Secret, with the certificate of the card it was set on.
func TestAFactoryAdoptionMarksItsSecret(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	s := h.secret()
	if _, err := time.Parse(time.RFC3339, s.Annotations[rackCardAdminSetAnnotation]); err != nil {
		t.Fatalf("%s = %q", rackCardAdminSetAnnotation, s.Annotations[rackCardAdminSetAnnotation])
	}
	if s.Annotations[rackCardAdminSetCertificateAnnotation] != h.card.Fingerprint() {
		t.Fatalf("%s = %q, want %q", rackCardAdminSetCertificateAnnotation, s.Annotations[rackCardAdminSetCertificateAnnotation], h.card.Fingerprint())
	}
}

// A card that briefly answers with a page instead of its API does not make an
// adopted object unadopted.
func TestAnAdoptedCardAnsweringUnexpectedlyStaysAdopted(t *testing.T) {
	t.Run("RackATS", func(t *testing.T) {
		h := newATSHarness(t, rackATS())
		h.reconcile()
		h.card.Mu.Lock()
		h.card.LegacyWeb = true
		h.card.Mu.Unlock()
		h.card.Expire()

		h.reconcile()

		ats := h.ats()
		if !ats.Status.Adopted || !conditions.IsTrue(ats, RackCardAdoptedCondition) {
			t.Fatalf("Adopted = %v, %+v; want still adopted", ats.Status.Adopted, conditions.Get(ats, RackCardAdoptedCondition))
		}
		if reason := conditions.GetReason(ats, clusterv1.ReadyCondition); reason != "UnexpectedResponse" {
			t.Fatalf("Ready reason %q, want UnexpectedResponse", reason)
		}
	})
	t.Run("RackPDU", func(t *testing.T) {
		h := newPDUHarness(t, rackPDU())
		h.reconcile()
		h.card.Mu.Lock()
		h.card.LegacyWeb = true
		h.card.Mu.Unlock()
		h.card.Expire()

		h.reconcile()

		pdu := h.pdu()
		if !pdu.Status.Adopted || !conditions.IsTrue(pdu, RackCardAdoptedCondition) {
			t.Fatalf("Adopted = %v, %+v; want still adopted", pdu.Status.Adopted, conditions.Get(pdu, RackCardAdoptedCondition))
		}
		if reason := conditions.GetReason(pdu, clusterv1.ReadyCondition); reason != "UnexpectedResponse" {
			t.Fatalf("Ready reason %q, want UnexpectedResponse", reason)
		}
	})
}
