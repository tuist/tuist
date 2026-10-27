package macos

import (
	"context"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

var powerNow = time.Date(2026, 11, 20, 10, 0, 0, 0, time.UTC)

func powerATS(name string, observed time.Time, amps, watts string) *infrav1.RackATS {
	at := metav1.NewTime(observed)
	return &infrav1.RackATS{
		ObjectMeta: metav1.ObjectMeta{Namespace: testNamespace, Name: name},
		Spec:       infrav1.RackATSSpec{Site: "ber1", Model: "eats16n", Address: "192.168.0.14"},
		Status: infrav1.RackATSStatus{
			LastObserved: &at,
			Outputs:      []infrav1.RackATSOutput{{Output: 1, Current: amps, Voltage: "230", ActivePower: watts}},
		},
	}
}

func powerPDU(name, chain string, read time.Time, outletAmps ...string) *infrav1.RackPDU {
	at := metav1.NewTime(read)
	pdu := &infrav1.RackPDU{
		ObjectMeta: metav1.ObjectMeta{Namespace: testNamespace, Name: name},
		Spec:       infrav1.RackPDUSpec{Site: "ber1", Model: "evmafc20a", Address: "192.168.0.16", Chain: chain},
		Status:     infrav1.RackPDUStatus{OutletsReadAt: &at},
	}
	for i, amps := range outletAmps {
		current := resource.MustParse(amps)
		watts := resource.MustParse("100")
		pdu.Status.Outlets = append(pdu.Status.Outlets, infrav1.RackPDUOutlet{
			Number:     i + 1,
			State:      "On",
			OutletDraw: infrav1.OutletDraw{CurrentAmps: &current, ActivePowerWatts: &watts},
		})
	}
	return pdu
}

func powerHost(name, pdu string) *infrav1.RackHost {
	return &infrav1.RackHost{
		ObjectMeta: metav1.ObjectMeta{Namespace: testNamespace, Name: name},
		Spec: infrav1.RackHostSpec{
			Location: infrav1.RackHostLocation{Site: "ber1"},
			Power:    &infrav1.PowerOutletRef{PDU: pdu, Outlet: "1"},
		},
		Status: infrav1.RackHostStatus{Machine: "rack-" + name},
	}
}

func powerNode(name string, taints ...corev1.Taint) *corev1.Node {
	return &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name}, Spec: corev1.NodeSpec{Taints: taints}}
}

func budgetedSite(chainAmps string, otherWatts int64) *infrav1.RackSite {
	site := rackSite(ber1ContractedPower()...)
	site.Spec.PowerBudget = &infrav1.RackSitePowerBudget{ChainAmps: resource.MustParse(chainAmps), OtherWatts: otherWatts}
	return site
}

type powerHarness struct {
	*siteHarness
}

func newPowerHarness(t *testing.T, objs ...client.Object) *powerHarness {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatalf("scheme: %v", err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatalf("scheme: %v", err)
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).WithStatusSubresource(&infrav1.RackSite{}).Build()
	h := &siteHarness{t: t, c: c, now: powerNow}
	h.r = &RackSiteReconciler{Client: c, Scheme: scheme, Now: func() time.Time { return h.now }}
	t.Cleanup(func() {
		rackSiteContractedPowerGauge.Reset()
		forgetRackSitePower("ber1")
	})
	return &powerHarness{h}
}

// taint is the power budget taint's value on the Node, "" without one.
func (h *powerHarness) taint(node string) string {
	h.t.Helper()
	got := &corev1.Node{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Name: node}, got); err != nil {
		h.t.Fatalf("get node %s: %v", node, err)
	}
	for _, taint := range got.Spec.Taints {
		if taint.Key == PowerBudgetTaintKey {
			if taint.Effect != corev1.TaintEffectNoSchedule {
				h.t.Fatalf("%s's taint effect = %s", node, taint.Effect)
			}
			return taint.Value
		}
	}
	return ""
}

// setATS replaces a transfer switch's observed output.
func (h *powerHarness) setATS(name string, observed time.Time, amps, watts string) {
	h.t.Helper()
	ats := &infrav1.RackATS{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: name}, ats); err != nil {
		h.t.Fatalf("get ats: %v", err)
	}
	ats.Status = powerATS(name, observed, amps, watts).Status
	if err := h.c.Update(context.Background(), ats); err != nil {
		h.t.Fatalf("update ats: %v", err)
	}
}

func TestPowerHoldHoldsAtTheLimitAndReleasesBelowItAfterTheMinimumHold(t *testing.T) {
	now := powerNow
	held, since := powerHold(13, 13, true, false, nil, now)
	if !held || since == nil || !since.Time.Equal(now) {
		t.Fatalf("at the limit: held=%v since=%v, want held since now", held, since)
	}
	later := now.Add(powerMinimumHold + time.Minute)
	if held, again := powerHold(12.6, 13, true, true, since, later); !held || again != since {
		t.Fatalf("within %.0f%% of the limit: held=%v, want still held since the start", powerReleaseFraction*100, held)
	}
	if held, _ := powerHold(12, 13, true, true, since, now.Add(time.Minute)); !held {
		t.Fatal("well under the limit inside the minimum hold: released, want still held")
	}
	if held, _ := powerHold(12, 13, true, true, since, later); held {
		t.Fatal("well under the limit after the minimum hold: still held, want released")
	}
	if held, _ := powerHold(15, 13, false, true, since, later); held {
		t.Fatal("no reading: held, want released (fail open)")
	}
	if held, _ := powerHold(15, 0, true, false, nil, later); held {
		t.Fatal("no limit: held, want nothing held")
	}
}

func TestATSReadingUsesCurrentTimesVoltageWithoutActivePowerAndIgnoresStaleObservations(t *testing.T) {
	r := atsReading(powerATS("ber1-ats-2", powerNow.Add(-time.Minute), "10", ""), powerNow)
	if !r.ok || r.amps != 10 || r.watts != 2300 {
		t.Fatalf("reading = %+v, want 10 A, 2300 W", r)
	}
	if r := atsReading(powerATS("ber1-ats-2", powerNow.Add(-atsReadingMaxAge-time.Second), "10", "2300"), powerNow); r.ok {
		t.Fatalf("stale observation read as %+v", r)
	}
	if r := atsReading(powerATS("ber1-ats-2", powerNow, "", ""), powerNow); r.ok {
		t.Fatalf("an output without current read as %+v", r)
	}
}

func TestPowerChainsFallBackToThePDUsAndLeaveLentHostsOut(t *testing.T) {
	stale := powerATS("ber1-ats-2", powerNow.Add(-time.Hour), "15", "3450")
	lent := powerHost("ber1-runner-b01", "ber1-pdu-a")
	lent.Spec.LendTo = "staging"
	chains := powerChains(
		[]*infrav1.RackATS{stale},
		[]*infrav1.RackPDU{powerPDU("ber1-pdu-a", "ber1-ats-2", powerNow.Add(-5*time.Minute), "1.5", "2"), powerPDU("lab-pdu", "", powerNow, "0.5")},
		[]*infrav1.RackHost{lent, powerHost("ber1-runner-b07", "ber1-pdu-a"), powerHost("lab-mini", "lab-pdu")},
		powerNow)
	if len(chains) != 2 || chains[0].name != "ber1-ats-2" || chains[1].name != "lab-pdu" {
		t.Fatalf("chains = %+v", chains)
	}
	ats := chains[0]
	if !ats.reading.ok || ats.reading.amps != 3.5 || ats.reading.watts != 200 {
		t.Fatalf("stale switch's chain read %+v, want its PDU's outlets, 3.5 A and 200 W", ats.reading)
	}
	if ats.hosts != 2 || len(ats.nodes) != 1 || ats.nodes[0] != "rack-ber1-runner-b07" {
		t.Fatalf("chain hosts=%d nodes=%v, want two hosts and only the unlent one's Node", ats.hosts, ats.nodes)
	}
	if lab := chains[1]; !lab.reading.ok || lab.reading.amps != 0.5 || len(lab.nodes) != 1 {
		t.Fatalf("a PDU on no switch: %+v", lab)
	}
}

// ber1's shape: chain A (ber1-ats-2, ber1-pdu-a) and chain B (ber1-ats-3,
// ber1-pdu-b), plus the critical switch ber1-ats-1 with no minis.
func ber1PowerObjects(chainAAmps, chainAWatts string) []client.Object {
	return []client.Object{
		powerATS("ber1-ats-1", powerNow, "2", "460"),
		powerATS("ber1-ats-2", powerNow, chainAAmps, chainAWatts),
		powerATS("ber1-ats-3", powerNow, "6", "1380"),
		powerPDU("ber1-pdu-a", "ber1-ats-2", powerNow),
		powerPDU("ber1-pdu-b", "ber1-ats-3", powerNow),
		powerHost("ber1-runner-b07", "ber1-pdu-a"),
		powerHost("ber1-runner-b08", "ber1-pdu-a"),
		powerHost("ber1-runner-b04", "ber1-pdu-b"),
		powerNode("rack-ber1-runner-b07", corev1.Taint{Key: "tuist.dev/macos", Value: "true", Effect: corev1.TaintEffectNoSchedule}),
		powerNode("rack-ber1-runner-b08"),
		powerNode("rack-ber1-runner-b04"),
	}
}

func TestAChainOverItsCurrentHoldsOnlyItsMinisUntilItDrawsLess(t *testing.T) {
	h := newPowerHarness(t, append(ber1PowerObjects("13.4", "1000"), budgetedSite("13", 0))...)

	res, site := h.reconcile()
	if res.RequeueAfter != rackSitePowerInterval {
		t.Fatalf("requeue after %v, want %v", res.RequeueAfter, rackSitePowerInterval)
	}
	if h.taint("rack-ber1-runner-b07") != "chain" || h.taint("rack-ber1-runner-b08") != "chain" {
		t.Fatal("chain A's minis are not held")
	}
	if h.taint("rack-ber1-runner-b04") != "" {
		t.Fatal("chain B's mini is held, but chain B is under its limit")
	}
	cond := conditions.Get(site, RackSitePowerAdmissionCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != "ChainOverBudget" {
		t.Fatalf("PowerAdmission = %+v, want False ChainOverBudget", cond)
	}
	if got := testutil.ToFloat64(rackSiteChainHeldGauge.WithLabelValues("ber1", "ber1-ats-2")); got != 1 {
		t.Fatalf("chain held = %v, want 1", got)
	}
	if got := testutil.ToFloat64(rackSiteChainCurrentGauge.WithLabelValues("ber1", "ber1-ats-2")); got != 13.4 {
		t.Fatalf("chain current = %v, want 13.4", got)
	}

	// Under the limit but within the release margin: still held.
	h.now = powerNow.Add(powerMinimumHold + time.Minute)
	h.setATS("ber1-ats-1", h.now, "2", "460")
	h.setATS("ber1-ats-3", h.now, "6", "1380")
	h.setATS("ber1-ats-2", h.now, "12.6", "1000")
	h.reconcile()
	if h.taint("rack-ber1-runner-b07") != "chain" {
		t.Fatal("released within the release margin")
	}

	h.setATS("ber1-ats-2", h.now, "11", "900")
	_, site = h.reconcile()
	if h.taint("rack-ber1-runner-b07") != "" || h.taint("rack-ber1-runner-b08") != "" {
		t.Fatal("chain A still held after it drew less for longer than the minimum hold")
	}
	if !conditions.IsTrue(site, RackSitePowerAdmissionCondition) {
		t.Fatalf("PowerAdmission = %+v, want True", conditions.Get(site, RackSitePowerAdmissionCondition))
	}
	if got := h.taintCount("rack-ber1-runner-b07"); got != 1 {
		t.Fatalf("b07 has %d taints, want only its tuist.dev/macos one", got)
	}
}

func (h *powerHarness) taintCount(node string) int {
	got := &corev1.Node{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Name: node}, got); err != nil {
		h.t.Fatalf("get node: %v", err)
	}
	return len(got.Spec.Taints)
}

func TestASiteOverItsContractedPowerHoldsEveryMini(t *testing.T) {
	// 3 kW contracted from 2026-10-05; the three switches draw 460 + 1500 + 1380.
	h := newPowerHarness(t, append(ber1PowerObjects("6", "1500"), budgetedSite("13", 0))...)

	_, site := h.reconcile()
	if site.Status.PowerBudgetWatts != 3000 || site.Status.MeteredWatts == nil || site.Status.MeteredWatts.Value() != 3340 {
		t.Fatalf("budget %d W, metered %v, want 3000 W and 3340 W", site.Status.PowerBudgetWatts, site.Status.MeteredWatts)
	}
	for _, node := range []string{"rack-ber1-runner-b07", "rack-ber1-runner-b08", "rack-ber1-runner-b04"} {
		if h.taint(node) != "site" {
			t.Fatalf("%s not held by the site", node)
		}
	}
	if cond := conditions.Get(site, RackSitePowerAdmissionCondition); cond == nil || cond.Reason != "SiteOverBudget" {
		t.Fatalf("PowerAdmission = %+v, want SiteOverBudget", cond)
	}
	if got := testutil.ToFloat64(rackSitePowerBudgetGauge.WithLabelValues("ber1")); got != 3000 {
		t.Fatalf("budget gauge = %v", got)
	}
}

func TestOtherWattsComesOffTheContractedPower(t *testing.T) {
	// larch's shape at its 6 kW step: 600 W of dual-PSU gear outside the switches.
	site := budgetedSite("11.5", 600)
	site.Spec.ContractedPower = []infrav1.RackSiteContractedPower{{From: "2026-11-09", Watts: 6000}}
	h := newPowerHarness(t, append(ber1PowerObjects("10", "2000"), site)...)
	_, got := h.reconcile()
	if got.Status.PowerBudgetWatts != 5400 {
		t.Fatalf("budget = %d W, want 5400", got.Status.PowerBudgetWatts)
	}
	if h.taint("rack-ber1-runner-b07") != "" {
		t.Fatal("held under both budgets")
	}
}

func TestStaleReadingsHoldNothingAndLiftAHold(t *testing.T) {
	objs := ber1PowerObjects("14", "1000")
	h := newPowerHarness(t, append(objs, budgetedSite("13", 0))...)
	h.reconcile()
	if h.taint("rack-ber1-runner-b07") != "chain" {
		t.Fatal("not held to begin with")
	}

	h.now = powerNow.Add(time.Hour)
	_, site := h.reconcile()
	if h.taint("rack-ber1-runner-b07") != "" {
		t.Fatal("still held on readings an hour old")
	}
	cond := conditions.Get(site, RackSitePowerAdmissionCondition)
	if cond == nil || cond.Status != corev1.ConditionUnknown || cond.Reason != "ReadingsStale" {
		t.Fatalf("PowerAdmission = %+v, want Unknown ReadingsStale", cond)
	}
	if site.Status.MeteredWatts != nil {
		t.Fatalf("metered watts = %v on stale readings", site.Status.MeteredWatts)
	}
}

func TestRemovingTheBudgetOrTheSiteLiftsEveryHold(t *testing.T) {
	h := newPowerHarness(t, append(ber1PowerObjects("14", "1000"), budgetedSite("13", 0))...)
	h.reconcile()

	site := &infrav1.RackSite{}
	key := types.NamespacedName{Namespace: testNamespace, Name: "ber1"}
	if err := h.c.Get(context.Background(), key, site); err != nil {
		t.Fatal(err)
	}
	site.Spec.PowerBudget = nil
	if err := h.c.Update(context.Background(), site); err != nil {
		t.Fatal(err)
	}
	res, got := h.reconcile()
	if h.taint("rack-ber1-runner-b07") != "" {
		t.Fatal("held without a budget")
	}
	if conditions.Get(got, RackSitePowerAdmissionCondition) != nil {
		t.Fatal("PowerAdmission set without a budget")
	}
	if want := time.Date(2027, 2, 5, 0, 0, 0, 0, time.UTC).Sub(h.now); res.RequeueAfter != want {
		t.Fatalf("without a budget, requeue after %v, want the next step's %v", res.RequeueAfter, want)
	}

	// Held again, then the RackSite goes.
	got.Spec.PowerBudget = &infrav1.RackSitePowerBudget{ChainAmps: resource.MustParse("13")}
	if err := h.c.Update(context.Background(), got); err != nil {
		t.Fatal(err)
	}
	h.reconcile()
	if h.taint("rack-ber1-runner-b07") != "chain" {
		t.Fatal("not held again")
	}
	if err := h.c.Delete(context.Background(), got); err != nil {
		t.Fatal(err)
	}
	if _, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: key}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if h.taint("rack-ber1-runner-b07") != "" {
		t.Fatal("held after its RackSite was deleted")
	}
}
