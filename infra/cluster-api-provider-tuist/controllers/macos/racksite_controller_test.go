package macos

import (
	"context"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

func rackSite(steps ...infrav1.RackSiteContractedPower) *infrav1.RackSite {
	return &infrav1.RackSite{
		ObjectMeta: metav1.ObjectMeta{Namespace: testNamespace, Name: "ber1"},
		Spec:       infrav1.RackSiteSpec{ContractedPower: steps},
	}
}

func ber1ContractedPower() []infrav1.RackSiteContractedPower {
	return []infrav1.RackSiteContractedPower{
		{From: "2027-06-05", Watts: 8000},
		{From: "2026-10-05", Watts: 3000},
		{From: "2027-02-05", Watts: 5000},
	}
}

type siteHarness struct {
	t   *testing.T
	c   client.Client
	r   *RackSiteReconciler
	now time.Time
}

func newSiteHarness(t *testing.T, now time.Time, objs ...client.Object) *siteHarness {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatalf("scheme: %v", err)
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).WithStatusSubresource(&infrav1.RackSite{}).Build()
	h := &siteHarness{t: t, c: c, now: now}
	h.r = &RackSiteReconciler{Client: c, Scheme: scheme, Now: func() time.Time { return h.now }}
	t.Cleanup(func() { rackSiteContractedPowerGauge.Reset() })
	return h
}

func (h *siteHarness) reconcile() (ctrl.Result, *infrav1.RackSite) {
	h.t.Helper()
	key := types.NamespacedName{Namespace: testNamespace, Name: "ber1"}
	res, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: key})
	if err != nil {
		h.t.Fatalf("Reconcile: %v", err)
	}
	site := &infrav1.RackSite{}
	if err := h.c.Get(context.Background(), key, site); err != nil {
		h.t.Fatalf("get: %v", err)
	}
	return res, site
}

func TestRackSiteExportsTheStepInEffectAndWakesAtTheNext(t *testing.T) {
	h := newSiteHarness(t, time.Date(2026, 10, 16, 11, 0, 0, 0, time.UTC), rackSite(ber1ContractedPower()...))

	res, site := h.reconcile()
	if got := testutil.ToFloat64(rackSiteContractedPowerGauge.WithLabelValues("ber1")); got != 3000 {
		t.Fatalf("contracted power = %v, want 3000", got)
	}
	if site.Status.ContractedPowerWatts != 3000 || site.Status.ContractedPowerSince != "2026-10-05" || site.Status.NextContractedPowerChange != "2027-02-05" {
		t.Fatalf("status = %+v", site.Status)
	}
	if want := time.Date(2027, 2, 5, 0, 0, 0, 0, time.UTC).Sub(h.now); res.RequeueAfter != want {
		t.Fatalf("requeue after %v, want %v", res.RequeueAfter, want)
	}

	h.now = time.Date(2027, 2, 5, 0, 0, 0, 0, time.UTC)
	_, site = h.reconcile()
	if got := testutil.ToFloat64(rackSiteContractedPowerGauge.WithLabelValues("ber1")); got != 5000 {
		t.Fatalf("contracted power on the step's first day = %v, want 5000", got)
	}
	if site.Status.NextContractedPowerChange != "2027-06-05" {
		t.Fatalf("next change = %q, want 2027-06-05", site.Status.NextContractedPowerChange)
	}

	h.now = time.Date(2028, 1, 1, 0, 0, 0, 0, time.UTC)
	res, site = h.reconcile()
	if got := testutil.ToFloat64(rackSiteContractedPowerGauge.WithLabelValues("ber1")); got != 8000 {
		t.Fatalf("contracted power after the last step = %v, want 8000", got)
	}
	if res.RequeueAfter != 0 || site.Status.NextContractedPowerChange != "" {
		t.Fatalf("after the last step: requeue %v, next change %q", res.RequeueAfter, site.Status.NextContractedPowerChange)
	}
}

func TestRackSiteHasNoSeriesBeforeItsFirstStep(t *testing.T) {
	h := newSiteHarness(t, time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC), rackSite(ber1ContractedPower()...))

	_, site := h.reconcile()
	if n := testutil.CollectAndCount(rackSiteContractedPowerGauge); n != 0 {
		t.Fatalf("%d series before the first step", n)
	}
	if site.Status.ContractedPowerWatts != 0 || site.Status.NextContractedPowerChange != "2026-10-05" {
		t.Fatalf("status = %+v", site.Status)
	}
}

func TestRackSiteWithAnUnreadableStepHasNoSeries(t *testing.T) {
	h := newSiteHarness(t, time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC),
		rackSite(infrav1.RackSiteContractedPower{From: "05.10.2026", Watts: 3000}))
	rackSiteContractedPowerGauge.WithLabelValues("ber1").Set(3000)

	_, site := h.reconcile()
	if n := testutil.CollectAndCount(rackSiteContractedPowerGauge); n != 0 {
		t.Fatalf("%d series for steps that cannot be read", n)
	}
	if site.Status.Message == "" || site.Status.ContractedPowerWatts != 0 {
		t.Fatalf("status = %+v", site.Status)
	}
}

func TestDeletedRackSiteDropsItsSeries(t *testing.T) {
	h := newSiteHarness(t, time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC))
	rackSiteContractedPowerGauge.WithLabelValues("ber1").Set(3000)

	if _, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: testNamespace, Name: "ber1"}}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if n := testutil.CollectAndCount(rackSiteContractedPowerGauge); n != 0 {
		t.Fatalf("%d series left for a deleted RackSite", n)
	}
}
