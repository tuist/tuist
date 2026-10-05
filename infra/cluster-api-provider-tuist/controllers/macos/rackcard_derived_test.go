package macos

import (
	"context"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackcard"
)

const testRootKey = "test-rack-card-root-key-0123456789"

var testRootKeyRef = types.NamespacedName{Namespace: "capt-system", Name: "rack-card-root"}

func testRootKeySecret() *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Namespace: testRootKeyRef.Namespace, Name: testRootKeyRef.Name},
		Data:       map[string][]byte{"key": []byte(testRootKey)},
	}
}

// derivedFor is what the controller derives for a card on site ber1.
func derivedFor(mac, name string) rackcard.Passwords {
	return rackcard.Derive([]byte(testRootKey), "ber1", rackcard.Identity(mac, name))
}

func pduPasswords() rackcard.Passwords { return derivedFor(rackPDU().Spec.MAC, "ber1-pdu-b") }
func atsPasswords() rackcard.Passwords { return derivedFor(rackATS().Spec.MAC, testATS) }

// legacySecret is a credentials Secret as an earlier build generated it, with
// random passwords, pinned to fingerprint.
func legacySecret(name, label, owner, address, fingerprint string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: testNamespace,
			Labels: map[string]string{label: owner, rackCardAddressLabel: address}},
		Data: map[string][]byte{
			"admin-username": []byte("admin"), "admin-password": []byte("Legacy-admin-pass1"),
			"username": []byte("tuist-controller"), "password": []byte("Legacy-ctrl-pass1"),
			"initial-password": []byte("Legacy-init-pass1"), "tlsFingerprint": []byte(fingerprint),
		},
	}
}

// onLegacyPasswords puts the card where an earlier build left it: the
// administrator and the controller's account on random passwords.
func onLegacyPasswords(card *eatontest.Card, profile string) {
	card.Mu.Lock()
	card.Accounts["0"].Password, card.Accounts["0"].PasswordExpired, card.Accounts["0"].Licence = "Legacy-admin-pass1", false, "accepted"
	card.Mu.Unlock()
	card.AddAccount("tuist-controller", "Legacy-ctrl-pass1", profile)
}

func assertSecretDerived(t *testing.T, secret *corev1.Secret, want rackcard.Passwords) {
	t.Helper()
	for key, value := range map[string]string{
		"admin-username": "admin", "admin-password": want.Admin,
		"username": "tuist-controller", "password": want.Controller, "initial-password": want.ControllerInitial,
	} {
		if got := string(secret.Data[key]); got != value {
			t.Fatalf("Secret %s = %q, want %q", key, got, value)
		}
	}
}

func TestRackPDUAdoptsAFactoryCardOntoDerivedPasswords(t *testing.T) {
	h := newPDUHarness(t, rackPDU())

	h.reconcile()

	h.assertAdopted()
	want := pduPasswords()
	if admin := h.card.Account("admin"); admin.Password != want.Admin {
		t.Fatalf("the card's administrator is on %q, want the derived %q", admin.Password, want.Admin)
	}
	if account := h.card.Account("tuist-controller"); account.Password != want.Controller {
		t.Fatalf("the controller's account is on %q, want the derived %q", account.Password, want.Controller)
	}
	assertSecretDerived(t, h.secret(), want)
	if h.eventsMatching("PasswordRotated") != 0 {
		t.Fatalf("events = %v; a factory card has nothing to rotate", h.events)
	}
}

// A card an earlier build adopted holds random passwords, recorded in its
// Secret. The next pass moves it onto the derived ones, though the object's
// generation did not change, and records them in the Secret.
func TestRackPDURotatesALegacyCardOntoDerivedPasswords(t *testing.T) {
	adopted := rackPDU(func(p *infrav1.RackPDU) { p.Status.Adopted, p.Status.ObservedGeneration = true, 1 })
	h := newPDUHarness(t, adopted)
	onLegacyPasswords(h.card, eatontest.ProfileOperators)
	for n := 1; n <= 4; n++ {
		h.card.Outlets[n].Settings["stateOnStartup"] = "on"
	}
	if err := h.r.Create(context.Background(), legacySecret("ber1-pdu-b-credentials", "tuist.dev/rack-pdu", "ber1-pdu-b", "192.168.0.16", h.card.Fingerprint())); err != nil {
		t.Fatal(err)
	}

	h.reconcile()

	h.assertAdopted()
	want := pduPasswords()
	if admin := h.card.Account("admin"); admin.Password != want.Admin {
		t.Fatalf("the card's administrator is on %q, want the derived %q", admin.Password, want.Admin)
	}
	if account := h.card.Account("tuist-controller"); account.Password != want.Controller {
		t.Fatalf("the controller's account is on %q, want the derived %q", account.Password, want.Controller)
	}
	secret := h.secret()
	assertSecretDerived(t, secret, want)
	if string(secret.Data["tlsFingerprint"]) != h.card.Fingerprint() || secret.Labels[rackCardAddressLabel] != "192.168.0.16" {
		t.Fatalf("the Secret lost its pin or its address: %v, %v", secret.Data["tlsFingerprint"], secret.Labels)
	}
	for _, role := range []string{"admin", "controller"} {
		if h.eventsMatching("PasswordRotated") == 0 || !h.anyEvent("PasswordRotated", role) {
			t.Fatalf("events = %v, want PasswordRotated for %s", h.events, role)
		}
	}

	// Rotated: the next pass only reads.
	before := adminAttempts(h.card)
	h.reconcile()
	if adminAttempts(h.card) != before {
		t.Fatal("a pass after the rotation logged the administrator in again")
	}
}

func (h *pduHarness) anyEvent(substrings ...string) bool {
	for _, e := range h.events {
		all := true
		for _, s := range substrings {
			all = all && strings.Contains(e, s)
		}
		if all {
			return true
		}
	}
	return false
}

// A cluster rebuilt from nothing has no credentials Secret. The card is
// already on the derived passwords, so the first login takes, nothing is
// done with the factory login, and the Secret is made again.
func TestRackPDUOnARebuiltClusterAdoptsWithTheDerivedPasswords(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	want := pduPasswords()
	h.card.Mu.Lock()
	h.card.Accounts["0"].Password, h.card.Accounts["0"].PasswordExpired, h.card.Accounts["0"].Licence = want.Admin, false, "accepted"
	h.card.Mu.Unlock()
	h.card.AddAccount("tuist-controller", want.Controller, eatontest.ProfileOperators)
	for n := 1; n <= 4; n++ {
		h.card.Outlets[n].Settings["stateOnStartup"] = "on"
	}

	h.reconcile()

	h.assertAdopted()
	if n := adminAttempts(h.card); n != 1 {
		t.Fatalf("%d administrator login attempts, want one with the derived password", n)
	}
	if w := h.writes(); len(w) != 0 {
		t.Fatalf("wrote %v to a card already on the derived passwords", w)
	}
	assertSecretDerived(t, h.secret(), want)
	if h.eventsMatching("CertificateRecorded") != 1 || h.eventsMatching("with the derived password") != 1 {
		t.Fatalf("events = %v, want the certificate pinned again and the derived login", h.events)
	}
}

// Without the root key nothing is derived, so nothing touches the card: no
// Secret, no login, no write.
func TestARackCardIsNotAdoptedWithoutTheRootKey(t *testing.T) {
	assertBlocked := func(t *testing.T, obj rackCard, card *eatontest.Card, secretErr error) {
		t.Helper()
		for _, c := range []clusterv1.ConditionType{RackCardAdoptedCondition, clusterv1.ReadyCondition} {
			cond := conditions.Get(obj, c)
			if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != "RootKeyMissing" ||
				!strings.Contains(cond.Message, "capt-system/rack-card-root") {
				t.Fatalf("%s = %+v, want False/RootKeyMissing naming the Secret", c, cond)
			}
		}
		card.Mu.Lock()
		attempts, writes := card.LoginAttempts, len(card.Writes)
		card.Mu.Unlock()
		if attempts != 0 || writes != 0 {
			t.Fatalf("contacted the card without the root key: %d logins, %d writes", attempts, writes)
		}
		if !apierrors.IsNotFound(secretErr) {
			t.Fatalf("credentials Secret without the root key: %v", secretErr)
		}
	}
	t.Run("RackPDU", func(t *testing.T) {
		h := newPDUHarness(t, rackPDU())
		if err := h.r.Delete(context.Background(), testRootKeySecret()); err != nil {
			t.Fatal(err)
		}
		res := h.reconcile()
		err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "ber1-pdu-b-credentials"}, &corev1.Secret{})
		assertBlocked(t, h.pdu(), h.card, err)
		if res.RequeueAfter <= 0 {
			t.Fatal("not looked at again for the root key")
		}
	})
	t.Run("RackATS", func(t *testing.T) {
		h := newATSHarness(t, rackATS())
		if err := h.r.Delete(context.Background(), testRootKeySecret()); err != nil {
			t.Fatal(err)
		}
		h.reconcile()
		err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: testATS + "-credentials"}, &corev1.Secret{})
		assertBlocked(t, h.ats(), h.card, err)
	})
	t.Run("a key too short", func(t *testing.T) {
		h := newPDUHarness(t, rackPDU())
		short := testRootKeySecret()
		short.Data["key"] = []byte("short")
		if err := h.r.Update(context.Background(), short); err != nil {
			t.Fatal(err)
		}
		h.reconcile()
		err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "ber1-pdu-b-credentials"}, &corev1.Secret{})
		assertBlocked(t, h.pdu(), h.card, err)
	})
}

// The administrator already on the derived password, the controller's
// account still on a random one: the account is moved onto the derived
// password, through the account being made again.
func TestRackATSMovesALegacyControllerAccountOntoTheDerivedPassword(t *testing.T) {
	adopted := rackATS(func(a *infrav1.RackATS) { a.Status.Adopted, a.Status.ObservedGeneration = true, 1 })
	h := newATSHarness(t, adopted)
	want := atsPasswords()
	onLegacyPasswords(h.card, eatontest.ProfileViewers)
	h.card.Mu.Lock()
	h.card.Accounts["0"].Password = want.Admin
	h.card.Mu.Unlock()
	legacy := legacySecret(testATS+"-credentials", "tuist.dev/rack-ats", testATS, "192.168.0.14", h.card.Fingerprint())
	legacy.Data["admin-password"] = []byte(want.Admin)
	if err := h.r.Create(context.Background(), legacy); err != nil {
		t.Fatal(err)
	}

	h.reconcile()

	h.assertAdopted(1)
	if account := h.card.Account("tuist-controller"); account.Password != want.Controller {
		t.Fatalf("the controller's account is on %q, want the derived %q", account.Password, want.Controller)
	}
	assertSecretDerived(t, h.secret(), want)
	if h.eventsMatching("PasswordRotated") != 1 || !strings.Contains(strings.Join(h.events, "\n"), "controller") {
		t.Fatalf("events = %v, want one PasswordRotated for the controller's account", h.events)
	}
	if n := adminAttempts(h.card); n != 1 {
		t.Fatalf("%d administrator login attempts, want the derived password only", n)
	}
}

// A legacy card on the transfer switch, through its whole lifecycle.
func TestRackATSRotatesALegacyCardOntoDerivedPasswords(t *testing.T) {
	adopted := rackATS(func(a *infrav1.RackATS) { a.Status.Adopted, a.Status.ObservedGeneration = true, 1 })
	h := newATSHarness(t, adopted)
	onLegacyPasswords(h.card, eatontest.ProfileViewers)
	if err := h.r.Create(context.Background(), legacySecret(testATS+"-credentials", "tuist.dev/rack-ats", testATS, "192.168.0.14", h.card.Fingerprint())); err != nil {
		t.Fatal(err)
	}

	h.reconcile()

	h.assertAdopted(1)
	want := atsPasswords()
	if admin := h.card.Account("admin"); admin.Password != want.Admin {
		t.Fatalf("the card's administrator is on %q, want the derived %q", admin.Password, want.Admin)
	}
	assertSecretDerived(t, h.secret(), want)
	if h.eventsMatching("PasswordRotated") != 2 {
		t.Fatalf("events = %v, want PasswordRotated for the administrator and the controller's account", h.events)
	}
}

// Nobody knows the card's administrator password: the derived one, the
// Secret's and the factory login are each tried once a pass, and the next
// pass waits out the backoff.
func TestTheAdministratorLoginsOfAPassAreBoundedAndBackedOff(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.card.Mu.Lock()
	h.card.Accounts["0"].Password, h.card.Accounts["0"].PasswordExpired = "Somebody-else1", false
	h.card.Mu.Unlock()
	if err := h.r.Create(context.Background(), legacySecret("ber1-pdu-b-credentials", "tuist.dev/rack-pdu", "ber1-pdu-b", "192.168.0.16", h.card.Fingerprint())); err != nil {
		t.Fatal(err)
	}
	now := h.clock()

	res := h.reconcile()
	if n := adminAttempts(h.card); n != 3 {
		t.Fatalf("%d administrator login attempts, want the derived, the Secret's and the factory one", n)
	}
	if reason := conditions.GetReason(h.pdu(), RackPDUAdoptedCondition); reason != "AdminLoginRefused" || res.RequeueAfter != time.Minute {
		t.Fatalf("Adopted reason %q, requeue %s", reason, res.RequeueAfter)
	}
	h.reconcile()
	if n := adminAttempts(h.card); n != 3 {
		t.Fatalf("%d administrator login attempts inside the backoff", n-3)
	}
	*now = now.Add(time.Minute)
	if res = h.reconcile(); res.RequeueAfter != 2*time.Minute || adminAttempts(h.card) != 6 {
		t.Fatalf("after the backoff: requeue %s, %d attempts", res.RequeueAfter, adminAttempts(h.card))
	}
	if string(h.secret().Data["admin-password"]) != "Legacy-admin-pass1" {
		t.Fatal("the Secret's administrator password was replaced while it was still the only other candidate")
	}
}

// A card that takes a login asking for the derived password but keeps its
// old one is not locked out: the Secret keeps the password that works, the
// object says the rotation did not apply, and the card stays managed and
// observed with it.
func TestARotationTheCardDoesNotApplyKeepsTheWorkingPassword(t *testing.T) {
	t.Run("RackATS", func(t *testing.T) {
		adopted := rackATS(func(a *infrav1.RackATS) { a.Status.Adopted, a.Status.ObservedGeneration = true, 1 })
		h := newATSHarness(t, adopted)
		onLegacyPasswords(h.card, eatontest.ProfileViewers)
		h.card.IgnoreNewPasswordUnlessExpired = true
		if err := h.r.Create(context.Background(), legacySecret(testATS+"-credentials", "tuist.dev/rack-ats", testATS, "192.168.0.14", h.card.Fingerprint())); err != nil {
			t.Fatal(err)
		}
		now := time.Now()
		h.r.adminBackoff.now = func() time.Time { return now }

		h.reconcile()

		assertRotationNotApplied(t, h.ats(), h.secret(), h.card)
		if h.eventsMatching("PasswordRotationNotApplied") != 1 || h.eventsMatching("Moved the card's admin password") != 0 {
			t.Fatalf("events = %v, want PasswordRotationNotApplied and no admin rotation", h.events)
		}
		if h.gauge("observed") != 1 || !conditions.IsTrue(h.ats(), clusterv1.ReadyCondition) {
			t.Fatal("the switch is not observed with the password that works")
		}

		// The next administrator pass, after its backoff, still gets in.
		before := h.adminLogins()
		h.reconcile()
		if h.adminLogins() != before {
			t.Fatal("logged the administrator in again inside the backoff")
		}
		now = now.Add(time.Hour)
		h.reconcile()
		if h.adminLogins() == before {
			t.Fatal("the administrator did not log in after the backoff")
		}
		assertRotationNotApplied(t, h.ats(), h.secret(), h.card)
	})
	t.Run("RackPDU", func(t *testing.T) {
		adopted := rackPDU(func(p *infrav1.RackPDU) { p.Status.Adopted, p.Status.ObservedGeneration = true, 1 })
		h := newPDUHarness(t, adopted)
		onLegacyPasswords(h.card, eatontest.ProfileOperators)
		h.card.IgnoreNewPasswordUnlessExpired = true
		if err := h.r.Create(context.Background(), legacySecret("ber1-pdu-b-credentials", "tuist.dev/rack-pdu", "ber1-pdu-b", "192.168.0.16", h.card.Fingerprint())); err != nil {
			t.Fatal(err)
		}

		h.reconcile()

		assertRotationNotApplied(t, h.pdu(), h.secret(), h.card)
		if !conditions.IsTrue(h.pdu(), clusterv1.ReadyCondition) {
			t.Fatalf("Ready = %+v; power still goes through the card", conditions.Get(h.pdu(), clusterv1.ReadyCondition))
		}
	})
}

func assertRotationNotApplied(t *testing.T, obj rackCard, secret *corev1.Secret, card *eatontest.Card) {
	t.Helper()
	if got := string(secret.Data["admin-password"]); got != "Legacy-admin-pass1" {
		t.Fatalf("the Secret records %q, want the password the card still has", got)
	}
	if admin := card.Account("admin"); admin.Password != "Legacy-admin-pass1" {
		t.Fatalf("setup: the card's administrator is on %q", admin.Password)
	}
	cond := conditions.Get(obj, RackCardAdoptedCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != "PasswordRotationNotApplied" {
		t.Fatalf("Adopted = %+v, want False/PasswordRotationNotApplied", cond)
	}
}

// A rotation the card took is proved with a fresh derived login before the
// Secret records it, and the password it replaced is kept beside it.
func TestAVerifiedRotationKeepsThePreviousPassword(t *testing.T) {
	adopted := rackPDU(func(p *infrav1.RackPDU) { p.Status.Adopted, p.Status.ObservedGeneration = true, 1 })
	h := newPDUHarness(t, adopted)
	onLegacyPasswords(h.card, eatontest.ProfileOperators)
	if err := h.r.Create(context.Background(), legacySecret("ber1-pdu-b-credentials", "tuist.dev/rack-pdu", "ber1-pdu-b", "192.168.0.16", h.card.Fingerprint())); err != nil {
		t.Fatal(err)
	}

	h.reconcile()

	h.assertAdopted()
	secret := h.secret()
	if string(secret.Data["admin-password"]) != pduPasswords().Admin || string(secret.Data["admin-password-previous"]) != "Legacy-admin-pass1" {
		t.Fatalf("Secret admin-password %q, admin-password-previous %q", secret.Data["admin-password"], secret.Data["admin-password-previous"])
	}
	// The derived login, the Secret's with the change, then the derived
	// login proving it.
	h.card.Mu.Lock()
	logins := strings.Join(h.card.LoginAttemptsBy, " ")
	h.card.Mu.Unlock()
	if !strings.HasPrefix(logins, "admin admin admin ") || adminAttempts(h.card) != 3 {
		t.Fatalf("logins %q, want three administrator logins", logins)
	}
}

// A card whose Secret records the derived password while the card still has
// the one before it is reached with the previous password and rotated.
func TestThePreviousAdminPasswordRecoversACard(t *testing.T) {
	adopted := rackPDU(func(p *infrav1.RackPDU) { p.Status.Adopted, p.Status.ObservedGeneration = true, 1 })
	h := newPDUHarness(t, adopted)
	onLegacyPasswords(h.card, eatontest.ProfileOperators)
	moved := legacySecret("ber1-pdu-b-credentials", "tuist.dev/rack-pdu", "ber1-pdu-b", "192.168.0.16", h.card.Fingerprint())
	moved.Data["admin-password"] = []byte(pduPasswords().Admin)
	moved.Data["admin-password-previous"] = []byte("Legacy-admin-pass1")
	if err := h.r.Create(context.Background(), moved); err != nil {
		t.Fatal(err)
	}

	h.reconcile()

	h.assertAdopted()
	if h.card.Account("admin").Password != pduPasswords().Admin {
		t.Fatal("the card was not moved onto the derived password")
	}
	if !h.anyEvent("PasswordRotated", "admin-password-previous") {
		t.Fatalf("events = %v, want the rotation to name the previous password", h.events)
	}
}
