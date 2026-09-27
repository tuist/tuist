package macos

import (
	"context"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
)

type pduHarness struct {
	t        *testing.T
	card     *eatontest.Card
	r        *RackPDUReconciler
	recorder *record.FakeRecorder
	events   []string
}

func rackPDU(mutate ...func(*infrav1.RackPDU)) *infrav1.RackPDU {
	pdu := &infrav1.RackPDU{
		ObjectMeta: metav1.ObjectMeta{Name: "ber1-pdu-b", Namespace: testNamespace, Generation: 1},
		Spec: infrav1.RackPDUSpec{
			Site: "ber1", Model: "evmafc20a", MAC: "00:20:85:d7:00:ca", Address: "192.168.0.16", Chain: "ber1-ats-2",
			ManagedBy: infrav1.RackCardManagedByController, OutletStateOnStartup: "on",
		},
	}
	for _, m := range mutate {
		m(pdu)
	}
	return pdu
}

// newPDUHarness starts a factory-fresh card with four outlets and a
// reconciler pointed at it.
func newPDUHarness(t *testing.T, objs ...runtime.Object) *pduHarness {
	t.Helper()
	card := eatontest.New(4)
	t.Cleanup(card.Close)
	previous := rackPDUHost
	rackPDUHost = func(*infrav1.RackPDU) string { return card.URL() }
	t.Cleanup(func() { rackPDUHost = previous })

	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{corev1.AddToScheme, infrav1.AddToScheme, clusterv1.AddToScheme} {
		if err := add(scheme); err != nil {
			t.Fatalf("scheme: %v", err)
		}
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.RackPDU{}).Build()
	recorder := record.NewFakeRecorder(100)
	eaton := &power.Eaton{SettleTimeout: time.Second, PollInterval: time.Millisecond}
	return &pduHarness{t: t, card: card, recorder: recorder, r: &RackPDUReconciler{
		Client: c, Scheme: scheme, Recorder: recorder, Timeout: 5 * time.Second,
		Power: eatonRegistry(eaton),
	}}
}

func (h *pduHarness) reconcile() ctrl.Result {
	h.t.Helper()
	res, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: testNamespace, Name: "ber1-pdu-b"}})
	if err != nil {
		h.t.Fatalf("Reconcile: %v", err)
	}
	for {
		select {
		case e := <-h.recorder.Events:
			h.events = append(h.events, e)
			continue
		default:
		}
		break
	}
	return res
}

func (h *pduHarness) pdu() *infrav1.RackPDU {
	h.t.Helper()
	pdu := &infrav1.RackPDU{}
	if err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "ber1-pdu-b"}, pdu); err != nil {
		h.t.Fatalf("get RackPDU: %v", err)
	}
	return pdu
}

func (h *pduHarness) secret() *corev1.Secret {
	h.t.Helper()
	s := &corev1.Secret{}
	if err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "ber1-pdu-b-credentials"}, s); err != nil {
		h.t.Fatalf("get credentials Secret: %v", err)
	}
	return s
}

func (h *pduHarness) eventsMatching(substring string) int {
	n := 0
	for _, e := range h.events {
		if strings.Contains(e, substring) {
			n++
		}
	}
	return n
}

func (h *pduHarness) writes() []string {
	h.card.Mu.Lock()
	defer h.card.Mu.Unlock()
	return append([]string(nil), h.card.Writes...)
}

func (h *pduHarness) assertAdopted() {
	h.t.Helper()
	pdu, secret := h.pdu(), h.secret()
	if !pdu.Status.Adopted || pdu.Status.ObservedGeneration != pdu.Generation || pdu.Status.Drift != infrav1.RackCardDriftNone {
		h.t.Fatalf("status = %+v, want adopted at generation %d with no drift", pdu.Status, pdu.Generation)
	}
	for _, c := range []clusterv1.ConditionType{RackPDUAdoptedCondition, RackPDUConvergedCondition, clusterv1.ReadyCondition} {
		if !conditions.IsTrue(pdu, c) {
			h.t.Fatalf("%s is not True: %+v", c, conditions.Get(pdu, c))
		}
	}
	admin := h.card.Account("admin")
	if admin.Password != string(secret.Data["admin-password"]) || admin.PasswordExpired || admin.Licence != "accepted" {
		h.t.Fatalf("admin = %+v, want the Secret's password and the licence accepted", admin)
	}
	account := h.card.Account("tuist-controller")
	if account == nil || account.Profile != eatontest.ProfileOperators || account.Password != string(secret.Data["password"]) ||
		account.PasswordExpired || account.Licence != "accepted" {
		h.t.Fatalf("controller account = %+v, want an operator on the Secret's password with the licence accepted", account)
	}
	for n := 1; n <= 4; n++ {
		if got := h.card.StateOnStartup(n); got != "on" {
			h.t.Fatalf("outlet %d starts %q, want on", n, got)
		}
	}
	if !power.SameTLSFingerprint(string(secret.Data["tlsFingerprint"]), h.card.Fingerprint()) || pdu.Status.TLSFingerprint == "" {
		h.t.Fatalf("pinned %q, card presents %q", secret.Data["tlsFingerprint"], h.card.Fingerprint())
	}
	if pdu.Status.SerialNumber != "421G456777" || pdu.Status.FirmwareVersion != "3.4.3" || pdu.Status.OutletCount != 4 {
		h.t.Fatalf("identification = %q/%q/%d", pdu.Status.SerialNumber, pdu.Status.FirmwareVersion, pdu.Status.OutletCount)
	}
}

func TestRackPDUAdoptsAFactoryCard(t *testing.T) {
	h := newPDUHarness(t, rackPDU())

	h.reconcile()

	h.assertAdopted()
	if h.eventsMatching("with the factory login") != 1 {
		t.Fatalf("events = %v, want one naming the factory login", h.events)
	}
	secret := h.secret()
	if len(secret.OwnerReferences) != 0 || secret.Labels["tuist.dev/rack-pdu"] != "ber1-pdu-b" {
		t.Fatalf("Secret owners = %+v, labels = %v; want no owner and the RackPDU's label", secret.OwnerReferences, secret.Labels)
	}
	// The administrator's session is logged out; the driver's stays for the
	// power paths.
	if n := h.card.OpenSessions(); n != 1 {
		t.Fatalf("%d sessions open on the card, want only the controller account's", n)
	}
	cond := conditions.Get(h.pdu(), RackPDUAddressReservedCondition)
	if cond == nil || cond.Status != corev1.ConditionTrue {
		t.Fatalf("AddressReserved = %+v, want True with a MAC", cond)
	}

	// Adopted: the next pass only reads.
	before := len(h.writes())
	h.reconcile()
	if after := h.writes(); len(after) != before {
		t.Fatalf("a pass at the same generation wrote %v", after[before:])
	}
}

// A pass that stopped after the Secret was written, before the card's
// password changed, finds the card on its factory login and finishes.
func TestRackPDUResumesBeforeThePasswordChanged(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	if _, err := h.r.ensureSecret(context.Background(), rackPDU()); err != nil {
		t.Fatal(err)
	}
	stored := h.secret().Data["admin-password"]

	h.reconcile()

	h.assertAdopted()
	if string(h.secret().Data["admin-password"]) != string(stored) {
		t.Fatal("the stored administrator password was replaced")
	}
}

// A pass that stopped after the card's password changed logs in with the
// stored password.
func TestRackPDUResumesAfterThePasswordChanged(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	if _, err := h.r.ensureSecret(context.Background(), rackPDU()); err != nil {
		t.Fatal(err)
	}
	h.card.Mu.Lock()
	admin := h.card.Accounts["0"]
	admin.Password, admin.PasswordExpired = string(h.secret().Data["admin-password"]), false
	h.card.Mu.Unlock()

	h.reconcile()

	h.assertAdopted()
	if h.eventsMatching("with the managed password") != 1 || h.eventsMatching("factory") != 0 {
		t.Fatalf("events = %v, want a login with the managed password", h.events)
	}
}

// The Secret holds the only copy of the passwords set on the card, so it
// outlives the RackPDU, and a RackPDU made again with the same name logs in
// with them rather than being refused by a card nobody knows the password of.
func TestRackPDUCredentialsOutliveTheRackPDU(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()
	h.assertAdopted()
	stored := h.secret().Data

	// Through the finalizer path too: the egress Service goes, the Secret stays.
	h.r.EgressNamespace, h.r.EgressProxyGroup = "tailscale-operator", "macmini-egress"
	pdu := h.pdu()
	pdu.Finalizers = []string{RackPDUFinalizer}
	if err := h.r.Update(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}
	if err := h.r.Delete(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}
	h.reconcile()
	err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "ber1-pdu-b"}, &infrav1.RackPDU{})
	if !apierrors.IsNotFound(err) {
		t.Fatalf("RackPDU after delete: %v", err)
	}
	secret := h.secret()
	if len(secret.OwnerReferences) != 0 {
		t.Fatalf("Secret owners = %+v; an owner would collect it with the RackPDU", secret.OwnerReferences)
	}
	h.r.EgressNamespace, h.r.EgressProxyGroup = "", ""

	if err := h.r.Create(context.Background(), rackPDU()); err != nil {
		t.Fatal(err)
	}
	h.events = nil
	h.card.Expire()
	h.reconcile()

	h.assertAdopted()
	if h.eventsMatching("with the managed password") != 1 || h.eventsMatching("factory") != 0 {
		t.Fatalf("events = %v, want a login with the stored password", h.events)
	}
	for _, key := range []string{"admin-password", "password", "initial-password", "tlsFingerprint"} {
		if string(h.secret().Data[key]) != string(stored[key]) {
			t.Fatalf("%s was replaced", key)
		}
	}
}

// A Secret an earlier build made with the RackPDU as its owner is released.
func TestRackPDUReleasesItsSecretFromAnOwner(t *testing.T) {
	owned := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: "ber1-pdu-b-credentials", Namespace: testNamespace,
		OwnerReferences: []metav1.OwnerReference{{APIVersion: "infrastructure.cluster.x-k8s.io/v1alpha1", Kind: "RackPDU", Name: "ber1-pdu-b", UID: "u"}}},
		Data: map[string][]byte{"admin-password": []byte("Kept-admin-password1")}}
	h := newPDUHarness(t, rackPDU(), owned)
	h.card.Mu.Lock()
	h.card.Accounts["0"].Password, h.card.Accounts["0"].PasswordExpired = "Kept-admin-password1", false
	h.card.Mu.Unlock()

	h.reconcile()

	h.assertAdopted()
	if s := h.secret(); len(s.OwnerReferences) != 0 || string(s.Data["admin-password"]) != "Kept-admin-password1" {
		t.Fatalf("Secret = owners %+v, admin-password %q", s.OwnerReferences, s.Data["admin-password"])
	}
}

func TestRackPDUChangedCertificateBlocksAndIsAcceptedByAnnotation(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()
	h.assertAdopted()
	old := h.card.Fingerprint()
	h.card.RotateCertificate()
	before := len(h.writes())

	h.reconcile()
	h.reconcile()

	pdu := h.pdu()
	if !conditions.IsTrue(pdu, RackPDUCertificateChangedCondition) || conditions.IsTrue(pdu, clusterv1.ReadyCondition) {
		t.Fatalf("conditions = %+v, want CertificateChanged and not Ready", pdu.Status.Conditions)
	}
	if pdu.Status.PresentedFingerprint != h.card.Fingerprint() || !power.SameTLSFingerprint(string(h.secret().Data["tlsFingerprint"]), old) {
		t.Fatalf("presented %q, pinned %q", pdu.Status.PresentedFingerprint, h.secret().Data["tlsFingerprint"])
	}
	if n := h.eventsMatching("CertificateChanged"); n != 1 {
		t.Fatalf("%d CertificateChanged events over two passes, want 1", n)
	}
	if after := h.writes(); len(after) != before {
		t.Fatalf("wrote %v to a card whose certificate changed", after[before:])
	}

	// An annotation naming another certificate changes nothing.
	pdu.Annotations = map[string]string{AcceptCertificateAnnotation: strings.Repeat("AB:", 31) + "AB"}
	if err := h.r.Update(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}
	h.reconcile()
	pdu = h.pdu()
	if _, still := pdu.Annotations[AcceptCertificateAnnotation]; still || !conditions.IsTrue(pdu, RackPDUCertificateChangedCondition) {
		t.Fatalf("after a wrong annotation: annotations %v, conditions %+v", pdu.Annotations, pdu.Status.Conditions)
	}

	pdu.Annotations = map[string]string{AcceptCertificateAnnotation: strings.ToLower(strings.ReplaceAll(h.card.Fingerprint(), ":", ""))}
	if err := h.r.Update(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}
	h.reconcile()
	pdu = h.pdu()
	if _, still := pdu.Annotations[AcceptCertificateAnnotation]; still {
		t.Fatal("the annotation stayed after acting")
	}
	if conditions.IsTrue(pdu, RackPDUCertificateChangedCondition) || !conditions.IsTrue(pdu, clusterv1.ReadyCondition) {
		t.Fatalf("after accepting: %+v", pdu.Status.Conditions)
	}
	if !power.SameTLSFingerprint(string(h.secret().Data["tlsFingerprint"]), h.card.Fingerprint()) {
		t.Fatal("the accepted certificate was not pinned")
	}
}

func TestRackPDUWithoutAMACIsAdoptedAndSaysItHasNoReservation(t *testing.T) {
	h := newPDUHarness(t, rackPDU(func(p *infrav1.RackPDU) { p.Spec.MAC = "" }))
	h.reconcile()
	h.assertAdopted()
	cond := conditions.Get(h.pdu(), RackPDUAddressReservedCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != "NoMAC" {
		t.Fatalf("AddressReserved = %+v, want False/NoMAC", cond)
	}
}

func TestUnreachableRackPDU(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.card.Close()

	res := h.reconcile()

	pdu := h.pdu()
	if pdu.Status.Reachable || pdu.Status.Adopted || res.RequeueAfter != rackPDURetryInterval {
		t.Fatalf("status = %+v, requeue %s", pdu.Status, res.RequeueAfter)
	}
	for _, c := range []clusterv1.ConditionType{RackPDUAdoptedCondition, clusterv1.ReadyCondition} {
		if cond := conditions.Get(pdu, c); cond == nil || cond.Reason != "Unreachable" {
			t.Fatalf("%s = %+v, want Unreachable", c, cond)
		}
	}
	// The credentials exist before the card is ever reached.
	if len(h.secret().Data["admin-password"]) == 0 {
		t.Fatal("no administrator password generated")
	}
}

func TestStandaloneRackPDUIsNeverContacted(t *testing.T) {
	h := newPDUHarness(t, rackPDU(func(p *infrav1.RackPDU) { p.Spec.ManagedBy = infrav1.RackCardManagedByStandalone }))
	h.reconcile()
	h.card.Mu.Lock()
	logins := len(h.card.Logins)
	h.card.Mu.Unlock()
	if logins != 0 || len(h.writes()) != 0 {
		t.Fatalf("contacted a standalone PDU: %d logins, writes %v", logins, h.writes())
	}
	if pdu := h.pdu(); !strings.Contains(pdu.Status.Message, "standalone") || pdu.Status.Adopted {
		t.Fatalf("status = %+v", pdu.Status)
	}
	err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "ber1-pdu-b-credentials"}, &corev1.Secret{})
	if !apierrors.IsNotFound(err) {
		t.Fatalf("made credentials for a standalone PDU: %v", err)
	}
}

// Drift is reported and left alone until the spec's next generation.
func TestRackPDUReportsDriftAndConvergesItOnANewGeneration(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()
	h.card.Mu.Lock()
	h.card.Outlets[2].Settings["stateOnStartup"] = "off"
	h.card.Mu.Unlock()
	before := len(h.writes())

	h.reconcile()
	h.reconcile()

	pdu := h.pdu()
	if pdu.Status.Drift != infrav1.RackCardDriftDrifted || conditions.IsTrue(pdu, RackPDUConvergedCondition) {
		t.Fatalf("status = %+v, want drifted", pdu.Status)
	}
	if !conditions.IsTrue(pdu, clusterv1.ReadyCondition) {
		t.Fatal("an outlet's startup state made the PDU not Ready; power still works")
	}
	if !strings.Contains(pdu.Status.Message, "2 (off)") || h.eventsMatching("Drifted") != 1 {
		t.Fatalf("message %q, events %v", pdu.Status.Message, h.events)
	}
	if h.card.StateOnStartup(2) != "off" || len(h.writes()) != before {
		t.Fatal("drift was written over at the same generation")
	}

	pdu.Generation = 2
	if err := h.r.Update(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}
	h.reconcile()
	if got := h.pdu(); got.Generation != 2 {
		t.Fatalf("generation = %d, want 2", got.Generation)
	}
	h.assertAdopted()
	if h.card.StateOnStartup(2) != "on" {
		t.Fatal("a new generation did not converge the outlet")
	}
}

// A controller account that no longer takes the Secret's password is made
// again on the next generation.
func TestRackPDURemakesAControllerAccountThatLostItsPassword(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()
	h.card.Mu.Lock()
	for _, a := range h.card.Accounts {
		if a.Name == "tuist-controller" {
			a.Password = "Somebody-else1"
		}
	}
	h.card.Mu.Unlock()
	h.card.Expire()

	h.reconcile()
	// A login that fails is not drift: nothing on the card was read.
	pdu0 := h.pdu()
	ready := conditions.Get(pdu0, clusterv1.ReadyCondition)
	if ready == nil || ready.Status == corev1.ConditionTrue || ready.Reason != "ControllerLoginFailed" {
		t.Fatalf("Ready = %+v, want False/ControllerLoginFailed", ready)
	}
	if pdu0.Status.Drift != infrav1.RackCardDriftUnknown || conditions.GetReason(pdu0, RackPDUConvergedCondition) == "Drifted" || h.eventsMatching("Drifted") != 0 {
		t.Fatalf("a login failure was reported as drift: %+v", pdu0.Status)
	}

	pdu := h.pdu()
	pdu.Generation = 2
	if err := h.r.Update(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}
	h.reconcile()
	h.assertAdopted()
	if h.eventsMatching("AccountRecreated") != 1 {
		t.Fatalf("events = %v", h.events)
	}
}

// Whatever the card says instead of a token on its first login is carried
// verbatim, so the first real contact shows what it wants.
func TestRackPDUFirstLoginRefusalIsReportedVerbatim(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.card.Refusal = &eatontest.Refusal{Status: 403, Body: `{"code":"LicenceNotAccepted","message":"accept the EULA first"}`}

	h.reconcile()

	cond := conditions.Get(h.pdu(), RackPDUAdoptedCondition)
	if cond == nil || cond.Reason != "FirstLoginBlocked" || !strings.Contains(cond.Message, `{"code":"LicenceNotAccepted","message":"accept the EULA first"}`) {
		t.Fatalf("Adopted = %+v", cond)
	}
}

func TestRackPDUAdminSessionHeldElsewhere(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.card.ForeignSessions["admin"] = true
	h.reconcile()
	if cond := conditions.Get(h.pdu(), RackPDUAdoptedCondition); cond == nil || cond.Reason != "AdminSessionBusy" {
		t.Fatalf("Adopted = %+v", cond)
	}
}

func TestRackPDUAdminPasswordNobodyKnows(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.card.Mu.Lock()
	h.card.Accounts["0"].Password = "Somebody-else1"
	h.card.Accounts["0"].PasswordExpired = false
	h.card.Mu.Unlock()
	h.reconcile()
	if cond := conditions.Get(h.pdu(), RackPDUAdoptedCondition); cond == nil || cond.Reason != "AdminLoginRefused" {
		t.Fatalf("Adopted = %+v", cond)
	}
}

func TestRackPDUEgressServiceIsKeptAndDeletedWithIt(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.r.EgressNamespace, h.r.EgressProxyGroup = "tailscale-operator", "macmini-egress"
	previous := rackPDUHost
	rackPDUHost = func(*infrav1.RackPDU) string { return "https://192.0.2.1:1" }
	t.Cleanup(func() { rackPDUHost = previous })
	h.r.Timeout = 50 * time.Millisecond

	h.reconcile()

	svc := &corev1.Service{}
	key := types.NamespacedName{Namespace: "tailscale-operator", Name: "rackpdu-ber1-pdu-b"}
	if err := h.r.Get(context.Background(), key, svc); err != nil {
		t.Fatalf("egress Service: %v", err)
	}
	if svc.Annotations["tailscale.com/tailnet-ip"] != "192.168.0.16" || len(svc.Spec.Ports) != 1 || svc.Spec.Ports[0].Port != 443 {
		t.Fatalf("Service = %+v", svc)
	}
	pdu := h.pdu()
	if len(pdu.Finalizers) != 1 {
		t.Fatalf("finalizers = %v", pdu.Finalizers)
	}
	if err := h.r.Delete(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}
	h.reconcile()
	if err := h.r.Get(context.Background(), key, svc); !apierrors.IsNotFound(err) {
		t.Fatalf("egress Service after the RackPDU was deleted: %v", err)
	}
}

func TestGeneratedCardPasswordsMeetTheCardsPolicy(t *testing.T) {
	for range 200 {
		p, err := generateCardPassword()
		if err != nil {
			t.Fatal(err)
		}
		var upper, lower, digit, special bool
		for _, r := range p {
			switch {
			case r >= 'A' && r <= 'Z':
				upper = true
			case r >= 'a' && r <= 'z':
				lower = true
			case r >= '0' && r <= '9':
				digit = true
			default:
				special = true
			}
		}
		if len(p) != 24 || !upper || !lower || !digit || !special {
			t.Fatalf("%q does not meet the policy", p)
		}
	}
}
