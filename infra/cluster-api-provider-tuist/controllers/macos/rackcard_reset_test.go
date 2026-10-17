package macos

import (
	"context"
	"testing"
	"time"

	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
)

// setAccountPassword changes an account's password on the card, as a person
// at its web UI would, and ends every session.
func setAccountPassword(card *eatontest.Card, name, password string) {
	card.Mu.Lock()
	for _, a := range card.Accounts {
		if a.Name == name {
			a.Password, a.PasswordExpired = password, false
		}
	}
	card.Mu.Unlock()
	card.Expire()
}

// A card reset to its factory state between generations is adopted again:
// the controller's refused login starts an adoption pass, which takes the
// factory login, makes the account again and reapplies the spec.
func TestAFactoryResetCardIsAdoptedAgain(t *testing.T) {
	t.Run("RackPDU", func(t *testing.T) {
		h := newPDUHarness(t, rackPDU())
		h.reconcile()
		h.assertAdopted()
		h.card.FactoryReset()
		h.events = nil

		h.reconcile()

		h.assertAdopted()
		if h.eventsMatching("with the factory login") != 1 {
			t.Fatalf("events = %v, want the factory login", h.events)
		}
	})
	t.Run("RackATS", func(t *testing.T) {
		h := newATSHarness(t, rackATS(prefers(2)))
		h.reconcile()
		h.assertAdopted(2)
		h.card.FactoryReset()
		h.events = nil

		h.reconcile()

		h.assertAdopted(2)
		if h.eventsMatching("with the factory login") != 1 {
			t.Fatalf("events = %v, want the factory login", h.events)
		}
	})
}

// A reset card that presents a new certificate is adopted again once the
// certificate is accepted.
func TestAFactoryResetCardWithANewCertificateIsAdoptedAgainOnceAccepted(t *testing.T) {
	t.Run("RackPDU", func(t *testing.T) {
		h := newPDUHarness(t, rackPDU())
		h.reconcile()
		h.assertAdopted()
		h.card.FactoryReset()
		h.card.RotateCertificate()

		h.reconcile()
		if !conditions.IsTrue(h.pdu(), RackCardCertificateChangedCondition) {
			t.Fatal("the new certificate was not reported")
		}
		pdu := h.pdu()
		pdu.Annotations = map[string]string{AcceptCertificateAnnotation: h.card.Fingerprint()}
		if err := h.r.Update(context.Background(), pdu); err != nil {
			t.Fatal(err)
		}
		h.events = nil
		h.reconcile()

		h.assertAdopted()
		if h.eventsMatching("with the factory login") != 1 {
			t.Fatalf("events = %v, want the factory login", h.events)
		}
	})
	t.Run("RackATS", func(t *testing.T) {
		h := newATSHarness(t, rackATS(prefers(2)))
		h.reconcile()
		h.assertAdopted(2)
		h.card.FactoryReset()
		h.card.RotateCertificate()

		h.reconcile()
		if !conditions.IsTrue(h.ats(), RackCardCertificateChangedCondition) {
			t.Fatal("the new certificate was not reported")
		}
		h.update(func(a *infrav1.RackATS) {
			a.Annotations = map[string]string{AcceptCertificateAnnotation: h.card.Fingerprint()}
		})
		h.events = nil
		h.reconcile()

		h.assertAdopted(2)
		if h.eventsMatching("with the factory login") != 1 {
			t.Fatalf("events = %v, want the factory login", h.events)
		}
	})
}

// A controller account someone changed the password of, on a card that was
// not reset, is made again on its derived password.
func TestAControllerAccountWithAWrongPasswordIsMadeAgain(t *testing.T) {
	t.Run("RackPDU", func(t *testing.T) {
		h := newPDUHarness(t, rackPDU())
		h.reconcile()
		setAccountPassword(h.card, "tuist-controller", "Somebody-else1")
		h.events = nil

		h.reconcile()

		h.assertAdopted()
		if h.eventsMatching("AccountRecreated") != 1 || h.eventsMatching("with the derived password") != 1 {
			t.Fatalf("events = %v, want the derived administrator login and the account made again", h.events)
		}
	})
	t.Run("RackATS", func(t *testing.T) {
		h := newATSHarness(t, rackATS())
		h.reconcile()
		setAccountPassword(h.card, "tuist-controller", "Somebody-else1")
		h.events = nil

		h.reconcile()

		h.assertAdopted(1)
		if h.eventsMatching("AccountRecreated") != 1 || h.eventsMatching("with the derived password") != 1 {
			t.Fatalf("events = %v, want the derived administrator login and the account made again", h.events)
		}
	})
}

// A card on which neither the controller's account nor the administrator
// logs in is tried later and later.
func TestAdoptingAgainAfterARefusedControllerLoginIsBackedOff(t *testing.T) {
	t.Run("RackPDU", func(t *testing.T) {
		h := newPDUHarness(t, rackPDU())
		h.reconcile()
		setAccountPassword(h.card, "tuist-controller", "Somebody-else1")
		setAccountPassword(h.card, "admin", "Somebody-else2")
		now := h.clock()
		admins := adminAttempts(h.card)

		res := h.reconcile()
		if res.RequeueAfter != time.Minute || adminAttempts(h.card) == admins {
			t.Fatalf("requeue %s after %d administrator attempts, want them tried and 1m", res.RequeueAfter, adminAttempts(h.card)-admins)
		}
		attempts := loginAttempts(h)
		h.reconcile()
		if loginAttempts(h) != attempts {
			t.Fatalf("%d logins inside the backoff", loginAttempts(h)-attempts)
		}
		*now = now.Add(time.Minute)
		if res = h.reconcile(); res.RequeueAfter != 2*time.Minute || loginAttempts(h) == attempts {
			t.Fatalf("after the backoff: requeue %s, want the logins tried again and 2m next", res.RequeueAfter)
		}
	})
	t.Run("RackATS", func(t *testing.T) {
		h := newATSHarness(t, rackATS())
		h.reconcile()
		setAccountPassword(h.card, "tuist-controller", "Somebody-else1")
		setAccountPassword(h.card, "admin", "Somebody-else2")
		now := h.clock()
		admins := adminAttempts(h.card)

		h.reconcile()
		if adminAttempts(h.card) == admins {
			t.Fatal("the administrator was not tried after the controller's login was refused")
		}
		if wait := h.r.adminBackoff.wait(h.ats()); wait != time.Minute {
			t.Fatalf("administrator backoff %s, want 1m", wait)
		}
		attempts := h.loginAttempts()
		h.reconcile()
		if h.loginAttempts() != attempts {
			t.Fatalf("%d logins inside the backoff", h.loginAttempts()-attempts)
		}
		*now = now.Add(time.Minute)
		h.reconcile()
		if wait := h.r.adminBackoff.wait(h.ats()); wait != 2*time.Minute || h.loginAttempts() == attempts {
			t.Fatalf("after the backoff: administrator backoff %s, want the logins tried again and 2m next", wait)
		}
	})
}
