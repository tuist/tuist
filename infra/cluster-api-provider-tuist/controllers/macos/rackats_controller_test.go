package macos

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
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
	"sigs.k8s.io/controller-runtime/pkg/event"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
)

const testATS = "ber1-ats-1"

type atsHarness struct {
	t        *testing.T
	card     *eatontest.Card
	r        *RackATSReconciler
	recorder *record.FakeRecorder
	events   []string
}

func rackATS(mutate ...func(*infrav1.RackATS)) *infrav1.RackATS {
	ats := &infrav1.RackATS{
		ObjectMeta: metav1.ObjectMeta{Name: testATS, Namespace: testNamespace, Generation: 1},
		Spec: infrav1.RackATSSpec{
			Site: "ber1", Model: "eats16n", MAC: "00:20:85:aa:bb:cc", Address: "192.168.0.14",
			ManagedBy: infrav1.RackCardManagedByController, PreferredSource: 1,
		},
	}
	for _, m := range mutate {
		m(ats)
	}
	return ats
}

func prefers(n int32) func(*infrav1.RackATS) {
	return func(a *infrav1.RackATS) { a.Spec.PreferredSource = n }
}

// newATSHarness starts a factory-fresh Network-M2 card in an EATS16N and a
// reconciler pointed at it.
func newATSHarness(t *testing.T, objs ...runtime.Object) *atsHarness {
	t.Helper()
	card := eatontest.NewATS()
	t.Cleanup(card.Close)
	previous := rackATSHost
	rackATSHost = func(*infrav1.RackATS) string { return card.URL() }
	t.Cleanup(func() { rackATSHost = previous })
	t.Cleanup(func() { forgetRackATSMetrics(testATS) })

	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{corev1.AddToScheme, infrav1.AddToScheme, clusterv1.AddToScheme} {
		if err := add(scheme); err != nil {
			t.Fatalf("scheme: %v", err)
		}
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.RackATS{}).Build()
	recorder := record.NewFakeRecorder(100)
	eaton := &power.Eaton{SettleTimeout: time.Second, PollInterval: time.Millisecond}
	return &atsHarness{t: t, card: card, recorder: recorder, r: &RackATSReconciler{
		Client: c, Scheme: scheme, Recorder: recorder, Timeout: 5 * time.Second,
		Power: eatonRegistry(eaton),
	}}
}

func (h *atsHarness) reconcile() ctrl.Result {
	h.t.Helper()
	res, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: testNamespace, Name: testATS}})
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

func (h *atsHarness) ats() *infrav1.RackATS {
	h.t.Helper()
	ats := &infrav1.RackATS{}
	if err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: testATS}, ats); err != nil {
		h.t.Fatalf("get RackATS: %v", err)
	}
	return ats
}

func (h *atsHarness) update(mutate func(*infrav1.RackATS)) {
	h.t.Helper()
	ats := h.ats()
	mutate(ats)
	if err := h.r.Update(context.Background(), ats); err != nil {
		h.t.Fatal(err)
	}
}

func (h *atsHarness) secret() *corev1.Secret {
	h.t.Helper()
	s := &corev1.Secret{}
	if err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: testATS + "-credentials"}, s); err != nil {
		h.t.Fatalf("get credentials Secret: %v", err)
	}
	return s
}

func (h *atsHarness) eventsMatching(substring string) int {
	n := 0
	for _, e := range h.events {
		if strings.Contains(e, substring) {
			n++
		}
	}
	return n
}

func (h *atsHarness) writes() []string {
	h.card.Mu.Lock()
	defer h.card.Mu.Unlock()
	return append([]string(nil), h.card.Writes...)
}

// adminLogins counts the administrator's logins: one per adoption pass.
func (h *atsHarness) adminLogins() int {
	h.card.Mu.Lock()
	defer h.card.Mu.Unlock()
	n := 0
	for _, name := range h.card.Logins {
		if name == "admin" {
			n++
		}
	}
	return n
}

func (h *atsHarness) condition(t clusterv1.ConditionType) *clusterv1.Condition {
	return conditions.Get(h.ats(), t)
}

func (h *atsHarness) gauge(name string, labels ...string) float64 {
	h.t.Helper()
	values := append([]string{testATS, "ber1"}, labels...)
	switch name {
	case "active_source":
		return testutil.ToFloat64(rackATSActiveSource.WithLabelValues(values...))
	case "preferred_source":
		return testutil.ToFloat64(rackATSPreferredSource.WithLabelValues(values...))
	case "redundant":
		return testutil.ToFloat64(rackATSRedundant.WithLabelValues(values...))
	case "input_good":
		return testutil.ToFloat64(rackATSInputGood.WithLabelValues(values...))
	case "input_voltage_volts":
		return testutil.ToFloat64(rackATSInputVoltage.WithLabelValues(values...))
	case "observed":
		return testutil.ToFloat64(rackATSObserved.WithLabelValues(values...))
	case "ready":
		return testutil.ToFloat64(rackATSReady.WithLabelValues(values...))
	case "adopted":
		return testutil.ToFloat64(rackATSAdopted.WithLabelValues(values...))
	case "drifted":
		return testutil.ToFloat64(rackATSDrifted.WithLabelValues(values...))
	case "certificate_changed":
		return testutil.ToFloat64(rackATSCertificateChanged.WithLabelValues(values...))
	case "observed_transfers_total":
		return testutil.ToFloat64(rackATSTransfers.WithLabelValues(values...))
	}
	h.t.Fatalf("no metric %s", name)
	return 0
}

func (h *atsHarness) assertAdopted(preferred int32) {
	h.t.Helper()
	ats, secret := h.ats(), h.secret()
	if !ats.Status.Adopted || ats.Status.ObservedGeneration != ats.Generation || ats.Status.Drift != infrav1.RackCardDriftNone {
		h.t.Fatalf("status = %+v, want adopted at generation %d with no drift", ats.Status, ats.Generation)
	}
	for _, c := range []clusterv1.ConditionType{RackCardAdoptedCondition, RackCardConvergedCondition, clusterv1.ReadyCondition} {
		if !conditions.IsTrue(ats, c) {
			h.t.Fatalf("%s is not True: %+v", c, conditions.Get(ats, c))
		}
	}
	admin := h.card.Account("admin")
	if admin.Password != string(secret.Data["admin-password"]) || admin.PasswordExpired || admin.Licence != "accepted" {
		h.t.Fatalf("admin = %+v, want the Secret's password and the licence accepted", admin)
	}
	account := h.card.Account("tuist-controller")
	if account == nil || account.Profile != eatontest.ProfileViewers || account.Password != string(secret.Data["password"]) ||
		account.PasswordExpired || account.Licence != "accepted" {
		h.t.Fatalf("controller account = %+v, want a viewer on the Secret's password with the licence accepted", account)
	}
	if got := h.card.PreferredSource(); got != int(preferred) {
		h.t.Fatalf("the card prefers source %d, want %d", got, preferred)
	}
	if ats.Status.PreferredSource != preferred {
		h.t.Fatalf("status.preferredSource = %d, want %d", ats.Status.PreferredSource, preferred)
	}
	if !power.SameTLSFingerprint(string(secret.Data["tlsFingerprint"]), h.card.Fingerprint()) || ats.Status.TLSFingerprint == "" {
		h.t.Fatalf("pinned %q, card presents %q", secret.Data["tlsFingerprint"], h.card.Fingerprint())
	}
	if ats.Status.DeviceSerialNumber != "GA1234567" || ats.Status.SerialNumber != "G212A01234" || !strings.Contains(ats.Status.Card, "Network-M2") {
		h.t.Fatalf("identification = card %q (serial %q), device serial %q", ats.Status.Card, ats.Status.SerialNumber, ats.Status.DeviceSerialNumber)
	}
}

func TestRackATSAdoptsAFactoryCardAndPrefersItsSource(t *testing.T) {
	h := newATSHarness(t, rackATS(prefers(2)))

	res := h.reconcile()

	h.assertAdopted(2)
	ats := h.ats()
	if ats.Status.ActiveSource != 2 || len(ats.Status.Inputs) != 2 || ats.Status.LastObserved == nil {
		t.Fatalf("observation = active %d, inputs %+v", ats.Status.ActiveSource, ats.Status.Inputs)
	}
	for _, in := range ats.Status.Inputs {
		if in.State != infrav1.RackATSInputGood || in.Voltage == "" {
			t.Fatalf("input = %+v, want good with a voltage", in)
		}
	}
	if !conditions.IsTrue(ats, RackATSRedundantCondition) {
		t.Fatalf("Redundant = %+v", conditions.Get(ats, RackATSRedundantCondition))
	}
	if res.RequeueAfter != rackATSObserveInterval {
		t.Fatalf("requeue after %s, want the observation interval", res.RequeueAfter)
	}
	if h.eventsMatching("with the factory login") != 1 || h.eventsMatching("Transferred") != 0 {
		t.Fatalf("events = %v, want one factory login and no transfer before the first observation", h.events)
	}
	secret := h.secret()
	if len(secret.OwnerReferences) != 0 || secret.Labels["tuist.dev/rack-ats"] != testATS {
		t.Fatalf("Secret owners = %+v, labels = %v", secret.OwnerReferences, secret.Labels)
	}
	if n := h.card.OpenSessions(); n != 1 {
		t.Fatalf("%d sessions open on the card, want only the controller account's", n)
	}
	for name, want := range map[string]float64{"active_source": 2, "preferred_source": 2, "redundant": 1, "observed": 1,
		"ready": 1, "adopted": 1, "drifted": 0, "certificate_changed": 0} {
		if got := h.gauge(name); got != want {
			t.Fatalf("capt_rackats_%s = %v, want %v", name, got, want)
		}
	}
	if got := h.gauge("input_good", "1"); got != 1 {
		t.Fatalf("capt_rackats_input_good{source=1} = %v", got)
	}
	if got := h.gauge("input_voltage_volts", "2"); got != 231.1 {
		t.Fatalf("capt_rackats_input_voltage_volts{source=2} = %v", got)
	}

	// One generation is one adoption: the next passes only read.
	before := len(h.writes())
	h.reconcile()
	h.reconcile()
	if after := h.writes(); len(after) != before {
		t.Fatalf("passes at the same generation wrote %v", after[before:])
	}
	if n := h.adminLogins(); n != 1 {
		t.Fatalf("the administrator logged in %d times for one generation", n)
	}
}

// A pass that stopped after the Secret was written, before the card's
// password changed, finds the card on its factory login and finishes; one
// that stopped after it changed logs in with the stored password.
func TestRackATSResumesAnInterruptedAdoption(t *testing.T) {
	for _, changed := range []bool{false, true} {
		h := newATSHarness(t, rackATS())
		if _, err := ensureRackCardSecret(context.Background(), h.r.Client, rackATS(), "tuist.dev/rack-ats"); err != nil {
			t.Fatal(err)
		}
		stored := string(h.secret().Data["admin-password"])
		if changed {
			h.card.Mu.Lock()
			h.card.Accounts["0"].Password, h.card.Accounts["0"].PasswordExpired = stored, false
			h.card.Mu.Unlock()
		}

		h.reconcile()

		h.assertAdopted(1)
		if string(h.secret().Data["admin-password"]) != stored {
			t.Fatal("the stored administrator password was replaced")
		}
		want := "with the factory login"
		if changed {
			want = "with the managed password"
		}
		if h.eventsMatching(want) != 1 {
			t.Fatalf("changed=%v: events = %v, want a login %s", changed, h.events, want)
		}
	}
}

func TestRackATSChangedCertificateBlocksAndIsAcceptedByAnnotation(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	h.assertAdopted(1)
	h.card.RotateCertificate()
	before := len(h.writes())

	h.reconcile()
	h.reconcile()

	ats := h.ats()
	if !conditions.IsTrue(ats, RackCardCertificateChangedCondition) || conditions.IsTrue(ats, clusterv1.ReadyCondition) {
		t.Fatalf("conditions = %+v, want CertificateChanged and not Ready", ats.Status.Conditions)
	}
	if cond := conditions.Get(ats, RackATSRedundantCondition); cond == nil || cond.Status != corev1.ConditionUnknown {
		t.Fatalf("Redundant = %+v, want Unknown while the card cannot be read", cond)
	}
	if h.eventsMatching("CertificateChanged") != 1 || len(h.writes()) != before {
		t.Fatalf("events %v, writes %v", h.events, h.writes()[before:])
	}
	if h.gauge("certificate_changed") != 1 || h.gauge("observed") != 0 || h.gauge("ready") != 0 {
		t.Fatal("the metrics do not show the changed certificate")
	}

	h.update(func(a *infrav1.RackATS) {
		a.Annotations = map[string]string{AcceptCertificateAnnotation: h.card.Fingerprint()}
	})
	h.reconcile()
	ats = h.ats()
	if _, still := ats.Annotations[AcceptCertificateAnnotation]; still {
		t.Fatal("the annotation stayed after acting")
	}
	if conditions.IsTrue(ats, RackCardCertificateChangedCondition) || !conditions.IsTrue(ats, clusterv1.ReadyCondition) ||
		!conditions.IsTrue(ats, RackATSRedundantCondition) {
		t.Fatalf("after accepting: %+v", ats.Status.Conditions)
	}
	if h.gauge("certificate_changed") != 0 || h.gauge("observed") != 1 {
		t.Fatal("the metrics still show the changed certificate")
	}
}

// Someone changing the preferred source at the web UI is reported and left
// alone until the spec's next generation, which converges it.
func TestRackATSReportsPreferredSourceDriftAndConvergesItOnANewGeneration(t *testing.T) {
	h := newATSHarness(t, rackATS(prefers(2)))
	h.reconcile()
	h.card.SetPreferredSource(1)
	before := len(h.writes())

	h.reconcile()
	h.reconcile()

	ats := h.ats()
	if ats.Status.Drift != infrav1.RackCardDriftDrifted || conditions.IsTrue(ats, RackCardConvergedCondition) {
		t.Fatalf("status = %+v, want drifted", ats.Status)
	}
	if !conditions.IsTrue(ats, clusterv1.ReadyCondition) || ats.Status.PreferredSource != 1 {
		t.Fatalf("a drifted preferred source made the switch %+v", ats.Status)
	}
	if !strings.Contains(ats.Status.Message, "preferred source is 1, not 2") || h.eventsMatching("Drifted") != 1 {
		t.Fatalf("message %q, events %v", ats.Status.Message, h.events)
	}
	if h.card.PreferredSource() != 1 || len(h.writes()) != before {
		t.Fatal("drift was written over at the same generation")
	}
	if h.gauge("drifted") != 1 || h.gauge("preferred_source") != 1 {
		t.Fatal("the metrics do not show the drift")
	}

	h.update(func(a *infrav1.RackATS) { a.Generation = 2 })
	h.reconcile()
	h.assertAdopted(2)
	if n := h.adminLogins(); n != 2 {
		t.Fatalf("%d administrator logins over two generations, want 2", n)
	}
	if h.gauge("drifted") != 0 {
		t.Fatal("capt_rackats_drifted stayed 1 after converging")
	}
}

func TestRackATSRedundancyLostAndRestored(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	h.card.SetSource(2, eatontest.SourceMissing, 0)

	h.reconcile()
	h.reconcile()

	cond := h.condition(RackATSRedundantCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != "AlternateSourceNotGood" ||
		!strings.Contains(cond.Message, "source 2, which the load would move to, is missing") {
		t.Fatalf("Redundant = %+v", cond)
	}
	if !conditions.IsTrue(h.ats(), clusterv1.ReadyCondition) {
		t.Fatal("a missing alternate source made the RackATS not Ready; observation works")
	}
	if h.gauge("redundant") != 0 || h.gauge("input_good", "2") != 0 || h.gauge("input_good", "1") != 1 || h.gauge("active_source") != 1 {
		t.Fatal("the metrics do not show the lost redundancy")
	}
	if h.eventsMatching("RedundancyLost") != 1 {
		t.Fatalf("events = %v, want one RedundancyLost over two passes", h.events)
	}

	h.card.SetSource(2, eatontest.SourceGood, 230.4)
	h.reconcile()
	if !conditions.IsTrue(h.ats(), RackATSRedundantCondition) || h.gauge("redundant") != 1 || h.eventsMatching("RedundancyRestored") != 1 {
		t.Fatalf("after restoring: %+v, events %v", h.condition(RackATSRedundantCondition), h.events)
	}
}

func TestRackATSReportsATransferWithAnEvent(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	transfers := h.gauge("observed_transfers_total", "1", "2")

	h.card.SetSource(1, eatontest.SourceOutOfRange, 180.2)
	h.reconcile()

	ats := h.ats()
	if ats.Status.ActiveSource != 2 || ats.Status.LastTransfer == nil || ats.Status.LastTransfer.From != 1 || ats.Status.LastTransfer.To != 2 {
		t.Fatalf("status = active %d, last transfer %+v", ats.Status.ActiveSource, ats.Status.LastTransfer)
	}
	if h.eventsMatching("Warning Transferred The load moved from source 1 to source 2") != 1 {
		t.Fatalf("events = %v", h.events)
	}
	if got := h.gauge("observed_transfers_total", "1", "2"); got != transfers+1 {
		t.Fatalf("capt_rackats_observed_transfers_total{from=1,to=2} = %v, want %v", got, transfers+1)
	}
	if in := rackATSInput(ats.Status.Inputs, 1); in == nil || in.State != infrav1.RackATSInputOutOfRange || in.Voltage != "180.2" {
		t.Fatalf("source 1 = %+v", in)
	}
	if cond := conditions.Get(ats, RackATSRedundantCondition); cond == nil || cond.Status != corev1.ConditionFalse {
		t.Fatalf("Redundant = %+v while on the alternate with the preferred out of range", cond)
	}

	h.card.SetSource(1, eatontest.SourceGood, 229.9)
	h.reconcile()
	if h.eventsMatching("Normal Transferred The load moved from source 2 to source 1") != 1 || h.ats().Status.ActiveSource != 1 {
		t.Fatalf("events = %v", h.events)
	}
}

func TestRackATSLoadNotPowered(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	h.card.SetSource(2, eatontest.SourceMissing, 0)
	h.card.SetSource(1, eatontest.SourceMissing, 0)
	h.reconcile()
	cond := h.condition(RackATSRedundantCondition)
	if cond == nil || cond.Reason != "LoadNotPowered" || h.ats().Status.ActiveSource != 0 || h.eventsMatching("LoadNotPowered") != 1 {
		t.Fatalf("Redundant = %+v, events %v", cond, h.events)
	}
	if h.gauge("active_source") != 0 || h.gauge("redundant") != 0 {
		t.Fatal("the metrics do not show the unpowered load")
	}
}

func TestRackATSUnsupportedCardIsReported(t *testing.T) {
	cases := map[string]struct {
		setup func(*eatontest.Card)
		want  string
	}{
		"a UPS at the address": {
			setup: func(c *eatontest.Card) { c.ATS.Type = "ups" },
			want:  `specifications.type "ups", not "ats"`,
		},
		"a card with no REST API": {
			setup: func(c *eatontest.Card) { c.LegacyWeb = true },
			want:  "404: <html>",
		},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			h := newATSHarness(t, rackATS())
			h.card.Mu.Lock()
			tc.setup(h.card)
			h.card.Mu.Unlock()

			res := h.reconcile()
			h.reconcile()

			ats := h.ats()
			for _, c := range []clusterv1.ConditionType{RackCardAdoptedCondition, clusterv1.ReadyCondition} {
				cond := conditions.Get(ats, c)
				if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != "UnsupportedCard" || !strings.Contains(cond.Message, tc.want) {
					t.Fatalf("%s = %+v, want False/UnsupportedCard saying %q", c, cond, tc.want)
				}
			}
			if ats.Status.Adopted || res.RequeueAfter != rackATSUnsupportedInterval || h.eventsMatching("UnsupportedCard") != 1 {
				t.Fatalf("status %+v, requeue %s, events %v", ats.Status, res.RequeueAfter, h.events)
			}
			if h.gauge("observed") != 0 || h.gauge("adopted") != 0 {
				t.Fatal("an unsupported card is reported as observed")
			}
			if h.card.Account("tuist-controller") != nil {
				t.Fatal("made an account on a card that is not a transfer switch")
			}
		})
	}
}

// A card whose settings name the preferred source in a way the controller
// does not know is adopted and observed, and says it cannot keep the
// preferred source.
func TestRackATSUnrecognisedPreferredSourceIsReported(t *testing.T) {
	h := newATSHarness(t, rackATS(prefers(2)))
	h.card.Mu.Lock()
	delete(h.card.ATS.Settings, "preferredInput")
	h.card.ATS.PreferredKey, h.card.ATS.Settings["sourcePriority"] = "sourcePriority", 1
	h.card.Mu.Unlock()

	h.reconcile()

	ats := h.ats()
	cond := conditions.Get(ats, RackCardConvergedCondition)
	if cond == nil || cond.Reason != "PreferredSourceUnrecognised" || !strings.Contains(cond.Message, "sourcePriority") {
		t.Fatalf("Converged = %+v", cond)
	}
	if !ats.Status.Adopted || !conditions.IsTrue(ats, clusterv1.ReadyCondition) || ats.Status.ActiveSource != 1 || ats.Status.PreferredSource != 0 {
		t.Fatalf("status = %+v", ats.Status)
	}
	if ats.Status.Drift == infrav1.RackCardDriftDrifted || h.eventsMatching("PreferredSourceUnrecognised") != 1 {
		t.Fatalf("drift %q, events %v", ats.Status.Drift, h.events)
	}
}

func TestRackATSWithoutAMACIsAdoptedAndSaysItHasNoReservation(t *testing.T) {
	h := newATSHarness(t, rackATS(func(a *infrav1.RackATS) { a.Spec.MAC = "" }))
	h.reconcile()
	h.assertAdopted(1)
	cond := h.condition(RackCardAddressReservedCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != "NoMAC" {
		t.Fatalf("AddressReserved = %+v, want False/NoMAC", cond)
	}
}

func TestStandaloneRackATSIsNeverContacted(t *testing.T) {
	h := newATSHarness(t, rackATS(func(a *infrav1.RackATS) { a.Spec.ManagedBy = infrav1.RackCardManagedByStandalone }))
	h.reconcile()
	h.card.Mu.Lock()
	logins := len(h.card.Logins)
	h.card.Mu.Unlock()
	if logins != 0 || len(h.writes()) != 0 {
		t.Fatalf("contacted a standalone ATS: %d logins, writes %v", logins, h.writes())
	}
	ats := h.ats()
	if cond := conditions.Get(ats, clusterv1.ReadyCondition); cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != "Standalone" {
		t.Fatalf("Ready = %+v, want False/Standalone", cond)
	}
	err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: testATS + "-credentials"}, &corev1.Secret{})
	if !apierrors.IsNotFound(err) {
		t.Fatalf("made credentials for a standalone ATS: %v", err)
	}
}

func TestUnreachableRackATS(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.card.Close()

	res := h.reconcile()

	ats := h.ats()
	if ats.Status.Reachable || ats.Status.Adopted || ats.Status.Drift != infrav1.RackCardDriftUnknown || res.RequeueAfter != rackATSRetryInterval {
		t.Fatalf("status = %+v, requeue %s", ats.Status, res.RequeueAfter)
	}
	for _, c := range []clusterv1.ConditionType{RackCardAdoptedCondition, clusterv1.ReadyCondition} {
		if cond := conditions.Get(ats, c); cond == nil || cond.Reason != "Unreachable" {
			t.Fatalf("%s = %+v, want Unreachable", c, cond)
		}
	}
	if cond := conditions.Get(ats, RackATSRedundantCondition); cond == nil || cond.Status != corev1.ConditionUnknown {
		t.Fatalf("Redundant = %+v, want Unknown", cond)
	}
	if len(h.secret().Data["admin-password"]) == 0 || h.gauge("observed") != 0 {
		t.Fatal("no credentials before first contact, or an unreachable switch reads as observed")
	}
}

// A controller account that cannot log in is a failed read, not drift.
func TestRackATSControllerLoginFailureIsNotDrift(t *testing.T) {
	h := newATSHarness(t, rackATS())
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

	ats := h.ats()
	cond := conditions.Get(ats, clusterv1.ReadyCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != "ControllerLoginFailed" {
		t.Fatalf("Ready = %+v, want False/ControllerLoginFailed", cond)
	}
	if ats.Status.Drift != infrav1.RackCardDriftUnknown || h.gauge("drifted") != 0 || h.gauge("observed") != 0 {
		t.Fatalf("drift %q: a failed login read as drift or as an observation", ats.Status.Drift)
	}
}

func TestRackATSEgressServiceIsKeptAndDeletedWithIt(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.r.EgressNamespace, h.r.EgressProxyGroup = "tailscale-operator", "macmini-egress"
	previous := rackATSHost
	rackATSHost = func(*infrav1.RackATS) string { return "https://192.0.2.1:1" }
	t.Cleanup(func() { rackATSHost = previous })
	h.r.Timeout = 50 * time.Millisecond

	h.reconcile()

	svc := &corev1.Service{}
	key := types.NamespacedName{Namespace: "tailscale-operator", Name: "rackats-" + testATS}
	if err := h.r.Get(context.Background(), key, svc); err != nil {
		t.Fatalf("egress Service: %v", err)
	}
	if svc.Annotations["tailscale.com/tailnet-ip"] != "192.168.0.14" || svc.Labels["tuist.dev/rack-ats"] != testATS || svc.Spec.Ports[0].Port != 443 {
		t.Fatalf("Service = %+v", svc)
	}
	ats := h.ats()
	if len(ats.Finalizers) != 1 || ats.Finalizers[0] != RackATSFinalizer {
		t.Fatalf("finalizers = %v", ats.Finalizers)
	}
	if err := h.r.Delete(context.Background(), ats); err != nil {
		t.Fatal(err)
	}
	h.reconcile()
	if err := h.r.Get(context.Background(), key, svc); !apierrors.IsNotFound(err) {
		t.Fatalf("egress Service after the RackATS was deleted: %v", err)
	}
	if err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: testATS + "-credentials"}, &corev1.Secret{}); err != nil {
		t.Fatalf("the credentials went with the RackATS: %v", err)
	}
}

// The controller's own status writes do not start another pass; a new
// generation, an annotation and a deletion do.
func TestRackATSEventsIgnoreStatusWrites(t *testing.T) {
	old := rackATS()
	statusOnly := old.DeepCopy()
	statusOnly.Status.Adopted = true
	statusOnly.ResourceVersion = "2"
	if rackATSEvents.Update(event.UpdateEvent{ObjectOld: old, ObjectNew: statusOnly}) {
		t.Fatal("a status write starts another pass")
	}
	generation := old.DeepCopy()
	generation.Generation = 2
	annotated := old.DeepCopy()
	annotated.Annotations = map[string]string{AcceptCertificateAnnotation: "x"}
	deleted := old.DeepCopy()
	now := metav1.Now()
	deleted.DeletionTimestamp = &now
	for name, updated := range map[string]*infrav1.RackATS{"generation": generation, "annotation": annotated, "deletion": deleted} {
		if !rackATSEvents.Update(event.UpdateEvent{ObjectOld: old, ObjectNew: updated}) {
			t.Fatalf("a %s change does not start a pass", name)
		}
	}
}
