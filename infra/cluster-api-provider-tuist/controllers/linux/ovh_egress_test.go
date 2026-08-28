package linux

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/client/interceptor"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

type fakeOVHAPI struct {
	body  any
	err   error
	calls int
}

func (f *fakeOVHAPI) GetWithContext(_ context.Context, _ string, res any) error {
	f.calls++
	if f.err != nil {
		return f.err
	}
	encoded, err := json.Marshal(f.body)
	if err != nil {
		return err
	}
	return json.Unmarshal(encoded, res)
}

func (f *fakeOVHAPI) PostWithContext(_ context.Context, _ string, _, _ any) error { return nil }
func (f *fakeOVHAPI) PutWithContext(_ context.Context, _ string, _, _ any) error  { return nil }
func (f *fakeOVHAPI) DeleteWithContext(_ context.Context, _ string, _ any) error  { return nil }

func egressBody(mbps int64, unit, tier string) map[string]any {
	return map[string]any{"bandwidth": map[string]any{
		"OvhToInternet": map[string]any{"unit": unit, "value": mbps},
		"type":          tier,
	}}
}

func egressScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	return scheme
}

func advertisedNodeMbps(t *testing.T, cl client.Client, name string) int32 {
	t.Helper()
	node := &corev1.Node{}
	if err := cl.Get(context.Background(), types.NamespacedName{Name: name}, node); err != nil {
		t.Fatalf("get node: %v", err)
	}
	return shared.NodeEgressMbps(node)
}

// egressHarness drives the real reconcileNodeEgress against a fake apiserver and
// asserts on what the Node advertises afterwards.
type egressHarness struct {
	t        *testing.T
	machine  *infrav1.OVHDedicatedMachine
	client   client.Client
	api      *fakeOVHAPI
	r        *OVHDedicatedMachineReconciler
	recorder *record.FakeRecorder
}

func newEgressHarness(t *testing.T) *egressHarness {
	t.Helper()
	machine := &infrav1.OVHDedicatedMachine{}
	machine.Name = "ovh-" + strings.ToLower(strings.ReplaceAll(t.Name(), "/", "-"))
	machine.Spec.EgressBudgetMbps = 3000
	machine.Spec.FleetName = "kura-us-east"
	machine.Status.ServiceName = "ns1.ip-1-2-3.us"
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: machine.Name}}
	cl := fake.NewClientBuilder().WithScheme(egressScheme(t)).WithObjects(node).WithStatusSubresource(node).Build()
	api := &fakeOVHAPI{body: map[string]any{}}
	recorder := record.NewFakeRecorder(100)
	r := &OVHDedicatedMachineReconciler{Client: cl, OVHClient: &ovh.Client{API: api}, Recorder: recorder}
	t.Cleanup(func() { shared.ForgetEgressMetrics(machine.Name) })
	return &egressHarness{t: t, machine: machine, client: cl, api: api, r: r, recorder: recorder}
}

// reports makes OVH answer mbps on the next reconcile and marks the read due.
func (h *egressHarness) reports(mbps int64) {
	h.api.err = nil
	h.api.body = egressBody(mbps, "Mbps", "improved")
	h.forceDue()
}

func (h *egressHarness) fails(err error) {
	h.api.err = err
	h.forceDue()
}

func (h *egressHarness) forceDue() {
	if h.machine.Status.Egress != nil {
		h.machine.Status.Egress.AttemptedAt = nil
	}
}

func (h *egressHarness) pin(mbps string) {
	if h.machine.Annotations == nil {
		h.machine.Annotations = map[string]string{}
	}
	h.machine.Annotations[shared.EgressOverrideAnnotation] = mbps
}

func (h *egressHarness) unpin() { delete(h.machine.Annotations, shared.EgressOverrideAnnotation) }

func (h *egressHarness) disable() {
	if h.machine.Annotations == nil {
		h.machine.Annotations = map[string]string{}
	}
	h.machine.Annotations[shared.DisableEgressDiscoveryAnnotation] = ""
}

func (h *egressHarness) enable() {
	delete(h.machine.Annotations, shared.DisableEgressDiscoveryAnnotation)
}

func (h *egressHarness) node() *corev1.Node {
	h.t.Helper()
	node := &corev1.Node{}
	if err := h.client.Get(context.Background(), types.NamespacedName{Name: h.machine.Name}, node); err != nil {
		h.t.Fatal(err)
	}
	return node
}

// step runs one reconcile and returns what the Node advertises and why.
func (h *egressHarness) step(name string) (int32, string) {
	h.t.Helper()
	if err := h.r.reconcileNodeEgress(context.Background(), h.machine, h.node()); err != nil {
		h.t.Fatalf("%s: %v", name, err)
	}
	source := ""
	if h.machine.Status.Egress != nil {
		source = h.machine.Status.Egress.Source
	}
	advertised := advertisedNodeMbps(h.t, h.client, h.machine.Name)
	h.t.Logf("%s -> node advertises %d (%s)", name, advertised, source)
	return advertised, source
}

func (h *egressHarness) want(name string, mbps int32, source string) {
	h.t.Helper()
	gotMbps, gotSource := h.step(name)
	if gotMbps != mbps || gotSource != source {
		h.t.Fatalf("%s: node advertises %d (%s), want %d (%s)", name, gotMbps, gotSource, mbps, source)
	}
}

func (h *egressHarness) wantCondition(status corev1.ConditionStatus, reason string) {
	h.t.Helper()
	cond := conditions.Get(h.machine, EgressDiscoveredCondition)
	if cond == nil {
		h.t.Fatalf("no %s condition, want %s/%s", EgressDiscoveredCondition, status, reason)
	}
	if cond.Status != status || cond.Reason != reason {
		h.t.Fatalf("%s = %s/%s (%s), want %s/%s", EgressDiscoveredCondition, cond.Status, cond.Reason, cond.Message, status, reason)
	}
}

func (h *egressHarness) drainEvents() []string {
	var events []string
	for {
		select {
		case e := <-h.recorder.Events:
			events = append(events, e)
		default:
			return events
		}
	}
}

func TestEgressDiscoveryRaisesAndNeverLowers(t *testing.T) {
	h := newEgressHarness(t)
	h.want("no reading yet", 3000, shared.EgressSourceConfigured)
	if h.api.calls != 1 {
		t.Fatalf("OVH calls = %d, want 1", h.api.calls)
	}

	h.reports(5000)
	h.want("OVH reports 5000", 5000, shared.EgressSourceDiscovery)
	h.wantCondition(corev1.ConditionTrue, "")
	h.want("steady state", 5000, shared.EgressSourceDiscovery)
	if h.api.calls != 2 {
		t.Fatalf("OVH calls = %d, want the cached reading reused within the refresh interval", h.api.calls)
	}

	h.reports(4000)
	h.want("OVH drops to 4000", 5000, shared.EgressSourceDiscovery)
	if h.machine.Status.Egress.ReportedMbps != 4000 {
		t.Fatalf("ReportedMbps = %d, want the lower reading recorded even though it is not applied", h.machine.Status.Egress.ReportedMbps)
	}

	// A kubelet re-registration wipes the capacity; status carries the intent.
	node := h.node()
	patch := client.MergeFrom(node.DeepCopy())
	delete(node.Status.Capacity, shared.EgressMbpsResource)
	if err := h.client.Status().Patch(context.Background(), node, patch); err != nil {
		t.Fatal(err)
	}
	h.want("after a kubelet re-registration", 5000, shared.EgressSourceDiscovery)
}

// The scenario from the review: spec 3000, OVH 4000, pinned to 8000 for a while,
// then unpinned. The pin is temporary, so the node lands on the reading.
func TestEgressPinIsTemporary(t *testing.T) {
	h := newEgressHarness(t)
	h.reports(4000)
	h.want("OVH reports 4000", 4000, shared.EgressSourceDiscovery)

	h.pin("8000")
	h.want("pinned to 8000", 8000, shared.EgressSourceManual)
	h.want("still pinned", 8000, shared.EgressSourceManual)

	h.unpin()
	h.want("unpinned", 4000, shared.EgressSourceDiscovery)
	h.want("steady state", 4000, shared.EgressSourceDiscovery)
}

// Accepting a reduction: pin, correct the configured budget, unpin. Unpinning
// before correcting the budget lands on the configured value, which is the floor.
func TestEgressAcceptingAReduction(t *testing.T) {
	h := newEgressHarness(t)
	h.reports(5000)
	h.want("OVH reports 5000", 5000, shared.EgressSourceDiscovery)

	h.reports(1000)
	h.pin("1000")
	h.want("operator pins 1000", 1000, shared.EgressSourceManual)

	h.unpin()
	h.want("unpinned with spec still 3000", 3000, shared.EgressSourceConfigured)

	h.pin("1000")
	h.machine.Spec.EgressBudgetMbps = 1000
	h.want("pinned again, spec corrected", 1000, shared.EgressSourceManual)
	h.unpin()
	h.want("unpinned with spec corrected", 1000, shared.EgressSourceConfigured)
}

func TestEgressPinNeedsAPositiveInteger(t *testing.T) {
	h := newEgressHarness(t)
	h.reports(5000)
	h.want("OVH reports 5000", 5000, shared.EgressSourceDiscovery)
	h.pin("lots")
	h.want("unparseable pin is ignored", 5000, shared.EgressSourceDiscovery)
	h.pin("0")
	h.want("zero pin is ignored", 5000, shared.EgressSourceDiscovery)
}

func TestEgressDisableFreezesTheNode(t *testing.T) {
	h := newEgressHarness(t)
	h.reports(5000)
	h.want("OVH reports 5000", 5000, shared.EgressSourceDiscovery)

	h.disable()
	h.reports(9000)
	calls := h.api.calls
	h.want("disabled: not lowered, not raised, not read", 5000, shared.EgressSourceDiscovery)
	h.wantCondition(corev1.ConditionFalse, EgressDiscoveryDisabledReason)
	if h.api.calls != calls {
		t.Fatalf("OVH was called while discovery is disabled")
	}

	h.pin("2000")
	h.want("a pin still applies while disabled", 2000, shared.EgressSourceManual)
	h.unpin()
	h.want("unpinned while disabled lands on spec", 3000, shared.EgressSourceConfigured)

	h.enable()
	h.machine.Status.Egress.AttemptedAt = &metav1.Time{Time: time.Now()}
	h.want("re-enabled: read at once, not after the refresh interval", 9000, shared.EgressSourceDiscovery)
	h.wantCondition(corev1.ConditionTrue, "")
}

func TestEgressARaisedConfiguredBudgetRaisesTheNode(t *testing.T) {
	h := newEgressHarness(t)
	h.reports(4000)
	h.want("OVH reports 4000", 4000, shared.EgressSourceDiscovery)
	h.machine.Spec.EgressBudgetMbps = 6000
	h.want("spec raised to 6000", 6000, shared.EgressSourceConfigured)
	h.machine.Spec.EgressBudgetMbps = 1000
	h.want("spec lowered alone changes nothing", 6000, shared.EgressSourceConfigured)
}

func TestEgressZeroBudgetWithdrawsTheNode(t *testing.T) {
	h := newEgressHarness(t)
	h.reports(5000)
	h.want("OVH reports 5000", 5000, shared.EgressSourceDiscovery)
	h.drainEvents()

	h.machine.Spec.EgressBudgetMbps = 0
	h.want("budget zeroed", 0, "")
	if h.machine.Status.Egress != nil {
		t.Fatal("status.egress should be cleared for an ungoverned machine")
	}
	if conditions.Has(h.machine, EgressDiscoveredCondition) {
		t.Fatal("the discovery condition should be removed for an ungoverned machine")
	}
	if _, ok := h.node().Status.Capacity[shared.EgressMbpsResource]; ok {
		t.Fatal("the capacity key should be removed")
	}
	events := h.drainEvents()
	if len(events) != 1 || !strings.Contains(events[0], "EgressBudgetRemoved") {
		t.Fatalf("events = %v, want one EgressBudgetRemoved", events)
	}

	// A pin on an ungoverned machine is ignored, and re-adding the budget brings
	// the box back through the normal path.
	h.pin("4000")
	h.want("pin on an ungoverned machine", 0, "")
	h.unpin()
	h.machine.Spec.EgressBudgetMbps = 3000
	h.want("budget restored", 5000, shared.EgressSourceDiscovery)
}

func TestEgressReAdoptionDropsTheOldBoxesReading(t *testing.T) {
	h := newEgressHarness(t)
	h.reports(5000)
	h.want("OVH reports 5000 for the first box", 5000, shared.EgressSourceDiscovery)

	h.machine.Status.ServiceName = "ns2.ip-4-5-6.us"
	h.api.body = egressBody(2000, "Mbps", "standard")
	h.want("re-adopted onto a 2000 box: node held at spec, not the old reading", 3000, shared.EgressSourceConfigured)
	egress := h.machine.Status.Egress
	if egress.ServiceName != "ns2.ip-4-5-6.us" || egress.ReportedMbps != 2000 {
		t.Fatalf("status.egress = %+v, want the new box read at once", egress)
	}
}

func TestEgressFailedReadKeepsTheLastReadingAndBacksOff(t *testing.T) {
	h := newEgressHarness(t)
	h.reports(5000)
	h.want("OVH reports 5000", 5000, shared.EgressSourceDiscovery)

	h.fails(errors.New("502 from OVH"))
	h.want("read fails", 5000, shared.EgressSourceDiscovery)
	h.wantCondition(corev1.ConditionFalse, EgressReadFailedReason)
	egress := h.machine.Status.Egress
	if egress.ReadFailures != 1 || egress.ReportedMbps != 5000 || egress.AttemptedAt == nil {
		t.Fatalf("status.egress = %+v, want one failure counted and the reading kept", egress)
	}

	calls := h.api.calls
	h.want("inside the retry interval", 5000, shared.EgressSourceDiscovery)
	if h.api.calls != calls {
		t.Fatal("a failed read was retried before the retry interval elapsed")
	}

	egress.AttemptedAt = &metav1.Time{Time: time.Now().Add(-egressReadRetryInterval)}
	h.want("after the retry interval", 5000, shared.EgressSourceDiscovery)
	if h.api.calls != calls+1 || egress.ReadFailures != 2 {
		t.Fatalf("calls = %d, failures = %d; want a retry counted", h.api.calls, egress.ReadFailures)
	}
	if cond := conditions.Get(h.machine, EgressDiscoveredCondition); !strings.Contains(cond.Message, "2 consecutive") {
		t.Fatalf("condition message = %q, want the failure count", cond.Message)
	}

	h.api.err = nil
	h.api.body = egressBody(6000, "Mbps", "improved")
	egress.AttemptedAt = &metav1.Time{Time: time.Now().Add(-egressReadRetryInterval)}
	h.want("OVH recovers", 6000, shared.EgressSourceDiscovery)
	if egress.ReadFailures != 0 {
		t.Fatalf("ReadFailures = %d, want reset on success", egress.ReadFailures)
	}
}

func TestEgressUnusableAnswerIsRecordedNotApplied(t *testing.T) {
	h := newEgressHarness(t)
	h.reports(5000)
	h.want("OVH reports 5000", 5000, shared.EgressSourceDiscovery)

	h.api.body = egressBody(5, "Gbit/s", "improved")
	h.forceDue()
	h.want("unknown unit", 5000, shared.EgressSourceDiscovery)
	h.wantCondition(corev1.ConditionFalse, EgressUnresolvedReason)
	egress := h.machine.Status.Egress
	if egress.ReportedMbps != 5000 || egress.ReadFailures != 0 {
		t.Fatalf("status.egress = %+v, want the last usable reading kept and no failure counted", egress)
	}

	calls := h.api.calls
	h.want("not re-read until the refresh interval", 5000, shared.EgressSourceDiscovery)
	if h.api.calls != calls {
		t.Fatal("an unusable answer was re-read before the refresh interval")
	}
}

func TestEgressReadDue(t *testing.T) {
	now := time.Now()
	r := &OVHDedicatedMachineReconciler{}
	machine := &infrav1.OVHDedicatedMachine{}
	at := func(d time.Duration) *metav1.Time { return &metav1.Time{Time: now.Add(-d)} }
	cases := []struct {
		name   string
		egress infrav1.EgressStatus
		want   bool
	}{
		{"never attempted", infrav1.EgressStatus{}, true},
		{"attempted just now", infrav1.EgressStatus{AttemptedAt: at(time.Minute)}, false},
		{"refresh interval elapsed", infrav1.EgressStatus{AttemptedAt: at(egressDiscoveryRefreshInterval)}, true},
		{"failing, inside the retry interval", infrav1.EgressStatus{AttemptedAt: at(time.Minute), ReadFailures: 1}, false},
		{"failing, retry interval elapsed", infrav1.EgressStatus{AttemptedAt: at(egressReadRetryInterval), ReadFailures: 1}, true},
	}
	for _, tc := range cases {
		egress := tc.egress
		if got := r.egressReadDue(machine, &egress, now); got != tc.want {
			t.Errorf("%s: due = %v, want %v", tc.name, got, tc.want)
		}
	}
}

func TestEgressEventsFireOnTransitionsOnly(t *testing.T) {
	h := newEgressHarness(t)
	h.want("seeded", 3000, shared.EgressSourceConfigured)
	h.reports(5000)
	h.want("raised", 5000, shared.EgressSourceDiscovery)
	h.want("steady", 5000, shared.EgressSourceDiscovery)
	h.reports(4000)
	h.want("lower reading refused", 5000, shared.EgressSourceDiscovery)
	h.pin("1000")
	h.want("pinned", 1000, shared.EgressSourceManual)

	events := h.drainEvents()
	want := []string{
		"EgressBudgetIncreased node egress budget set to 3000 Mbps (spec.egressBudgetMbps)",
		"EgressBudgetIncreased node egress budget raised from 3000 to 5000 Mbps (reported by OVH for ns1.ip-1-2-3.us)",
		"EgressBudgetReduced node egress budget reduced from 5000 to 1000 Mbps (pinned by tuist.dev/egress-mbps-override)",
	}
	if len(events) != len(want) {
		t.Fatalf("events = %v, want %v", events, want)
	}
	for i := range want {
		if !strings.HasSuffix(events[i], want[i]) {
			t.Fatalf("event %d = %q, want suffix %q", i, events[i], want[i])
		}
	}
}

// Status carries the intent, so a failed node patch is retried by the next
// reconcile from the same status rather than re-derived from a stale node.
func TestEgressFailedNodePatchIsRetriedFromStatus(t *testing.T) {
	scheme := egressScheme(t)
	machine := &infrav1.OVHDedicatedMachine{}
	machine.Name = "ovh-patch-fails"
	machine.Spec.EgressBudgetMbps = 3000
	machine.Status.ServiceName = "ns1.ip-1-2-3.us"
	machine.Status.Egress = &infrav1.EgressStatus{
		ServiceName: "ns1.ip-1-2-3.us", BudgetMbps: 8000, Source: shared.EgressSourceManual,
		ReportedMbps: 4000, AttemptedAt: &metav1.Time{Time: time.Now()},
	}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: machine.Name}}
	node.Status.Capacity = corev1.ResourceList{shared.EgressMbpsResource: resource.MustParse("8000")}
	t.Cleanup(func() { shared.ForgetEgressMetrics(machine.Name) })

	failing := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node).WithStatusSubresource(node).
		WithInterceptorFuncs(interceptor.Funcs{
			SubResourcePatch: func(context.Context, client.Client, string, client.Object, client.Patch, ...client.SubResourcePatchOption) error {
				return errors.New("apiserver said no")
			},
		}).Build()
	r := &OVHDedicatedMachineReconciler{Client: failing, OVHClient: &ovh.Client{API: &fakeOVHAPI{err: errors.New("not read on this path")}}}

	if err := r.reconcileNodeEgress(context.Background(), machine, node.DeepCopy()); err == nil {
		t.Fatal("a failed capacity patch should surface as an error")
	}
	if got := machine.Status.Egress; got.BudgetMbps != 4000 || got.Source != shared.EgressSourceDiscovery {
		t.Fatalf("status.egress = %+v, want the re-derived 4000/discovery recorded despite the failed patch", got)
	}

	working := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node).WithStatusSubresource(node).Build()
	r.Client = working
	fresh := &corev1.Node{}
	if err := working.Get(context.Background(), types.NamespacedName{Name: machine.Name}, fresh); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileNodeEgress(context.Background(), machine, fresh); err != nil {
		t.Fatalf("retry: %v", err)
	}
	if got := advertisedNodeMbps(t, working, machine.Name); got != 4000 {
		t.Fatalf("node advertises %d, want 4000", got)
	}
}

// The reported gauge is republished from status on every reconcile, so it does
// not vanish for a day after an operator restart.
func TestEgressReportedGaugeSurvivesARestart(t *testing.T) {
	h := newEgressHarness(t)
	h.reports(5000)
	h.want("OVH reports 5000", 5000, shared.EgressSourceDiscovery)

	shared.ForgetEgressMetrics(h.machine.Name) // what a restart does to process-local gauges
	if got := reportedGauge(t, h.machine.Name); got != nil {
		t.Fatalf("reported gauge = %v before the reconcile, want none", *got)
	}
	h.want("next reconcile, no read due", 5000, shared.EgressSourceDiscovery)
	if got := reportedGauge(t, h.machine.Name); got == nil || *got != 5000 {
		t.Fatalf("reported gauge = %v, want 5000 republished from status", got)
	}
}

func reportedGauge(t *testing.T, node string) *float64 {
	t.Helper()
	families, err := metrics.Registry.Gather()
	if err != nil {
		t.Fatal(err)
	}
	for _, family := range families {
		if family.GetName() != "capt_egress_reported_mbps" {
			continue
		}
		for _, m := range family.GetMetric() {
			for _, label := range m.GetLabel() {
				if label.GetName() == "node" && label.GetValue() == node {
					v := m.GetGauge().GetValue()
					return &v
				}
			}
		}
	}
	return nil
}
