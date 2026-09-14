package macos

import (
	"context"
	"errors"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

func newRackHostReconciler(t *testing.T, driver power.Driver, objs ...runtime.Object) *RackHostReconciler {
	t.Helper()
	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{
		corev1.AddToScheme, infrav1.AddToScheme, clusterv1.AddToScheme,
	} {
		if err := add(scheme); err != nil {
			t.Fatalf("scheme: %v", err)
		}
	}
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.RackHost{}, &infrav1.RackAppleSiliconMachine{}).
		Build()
	r := &RackHostReconciler{
		Client:           c,
		Recorder:         fakeRecorder(),
		SecretsNamespace: testNamespace,
		PowerCycleSettle: time.Millisecond,
	}
	if driver != nil {
		r.Power = registryWithShelly(driver)
	}
	return r
}

func reconcileHost(t *testing.T, r *RackHostReconciler, name string) ctrl.Result {
	t.Helper()
	res, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{Namespace: testNamespace, Name: name},
	})
	if err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	return res
}

func readHost(t *testing.T, r *RackHostReconciler, name string) *infrav1.RackHost {
	t.Helper()
	h := &infrav1.RackHost{}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: name}, h); err != nil {
		t.Fatalf("get %s: %v", name, err)
	}
	return h
}

func node(name string, ready bool, mutate ...func(*corev1.Node)) *corev1.Node {
	status := corev1.ConditionFalse
	if ready {
		status = corev1.ConditionTrue
	}
	n := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name},
		Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{
			{Type: corev1.NodeReady, Status: status},
		}},
	}
	for _, m := range mutate {
		m(n)
	}
	return n
}

// --- power observation ------------------------------------------------------

func TestReconcileRecordsObservedPowerState(t *testing.T) {
	driver := &stubPowerDriver{on: true}
	r := newRackHostReconciler(t, driver, rackHost("mini-01"))

	res := reconcileHost(t, r, "mini-01")
	if res.RequeueAfter != powerPollInterval {
		t.Fatalf("RequeueAfter = %v, want the poll interval %v", res.RequeueAfter, powerPollInterval)
	}

	host := readHost(t, r, "mini-01")
	if host.Status.Power != string(power.StateOn) {
		t.Fatalf("Power = %q, want On", host.Status.Power)
	}
	if cond := conditionOf(host, PowerReachableCondition); cond == nil || cond.Status != corev1.ConditionTrue {
		t.Fatalf("PowerReachable = %+v, want True", cond)
	}
}

// An unreachable plug must report Unknown, never Off: those two want opposite
// responses from whoever is looking, and reporting Off for "we could not ask"
// says the host was deliberately shut down.
func TestUnreachableOutletReportsUnknownRatherThanOff(t *testing.T) {
	r := newRackHostReconciler(t, &erroringDriver{}, rackHost("mini-01"))

	reconcileHost(t, r, "mini-01")

	host := readHost(t, r, "mini-01")
	if host.Status.Power != string(power.StateUnknown) {
		t.Fatalf("Power = %q, want Unknown", host.Status.Power)
	}
	cond := conditionOf(host, PowerReachableCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != "PowerUnreachable" {
		t.Fatalf("condition = %+v, want False/PowerUnreachable", cond)
	}
}

// A host with no outlet is a host nobody can reboot remotely. It is not an
// error (the box may be fine) but it has to be visible before the reboot is
// needed rather than at the moment it cannot be done.
func TestHostWithoutAnOutletIsFlaggedButStillReconciled(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Spec.Power = nil })
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, host)

	res := reconcileHost(t, r, "mini-01")
	if res.RequeueAfter == 0 {
		t.Fatal("reconcile gave up on a host with no outlet")
	}
	got := readHost(t, r, "mini-01")
	cond := conditionOf(got, PowerReachableCondition)
	if cond == nil || cond.Reason != "PowerNotConfigured" {
		t.Fatalf("condition = %+v, want PowerNotConfigured", cond)
	}
}

func TestPowerCredentialsAreReadFromTheReferencedSecret(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Spec.Power.CredentialsSecretRef = &corev1.LocalObjectReference{Name: "pdu"}
	})
	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "pdu", Namespace: testNamespace},
		Data:       map[string][]byte{"username": []byte("admin"), "password": []byte("hunter2")},
	}
	driver := &credentialRecordingDriver{}
	r := newRackHostReconciler(t, driver, host, secret)

	reconcileHost(t, r, "mini-01")

	if driver.username != "admin" || driver.password != "hunter2" {
		t.Fatalf("driver saw %q/%q, want the Secret's credentials", driver.username, driver.password)
	}
}

func TestMissingPowerSecretIsSurfacedNotIgnored(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Spec.Power.CredentialsSecretRef = &corev1.LocalObjectReference{Name: "pdu"}
	})
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, host)

	reconcileHost(t, r, "mini-01")

	cond := conditionOf(readHost(t, r, "mini-01"), PowerReachableCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse {
		t.Fatalf("condition = %+v, want False when the credential Secret is missing", cond)
	}
}

// --- orphan reclaim ---------------------------------------------------------

// A claim whose machine is gone strands a physical box: nothing else releases
// it, and in a rack sized to demand that is capacity a scale-up will wait on
// forever while the machine sits idle in front of someone.
func TestOrphanedClaimIsReleased(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Status.ClaimedBy = "ber1-0"
		h.Status.ClaimedAt = &metav1.Time{Time: time.Now()}
	})
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, host)

	reconcileHost(t, r, "mini-01")

	got := readHost(t, r, "mini-01")
	if got.Status.ClaimedBy != "" || got.Status.ClaimedAt != nil {
		t.Fatalf("orphaned claim survived: %+v", got.Status)
	}
}

func TestLiveClaimIsLeftAlone(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.ClaimedBy = "ber1-0" })
	machine := rackMachine("ber1-0")
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, host, machine)

	reconcileHost(t, r, "mini-01")

	if got := readHost(t, r, "mini-01"); got.Status.ClaimedBy != "ber1-0" {
		t.Fatal("released a claim whose machine still exists; two machines could then hold one box")
	}
}

// --- operator power actions -------------------------------------------------

func TestPowerActionRunsAndClearsItsAnnotation(t *testing.T) {
	for _, tc := range []struct {
		action string
		want   []string
	}{
		{"on", []string{"set=true"}},
		{"off", []string{"set=false"}},
		{"cycle", []string{"set=false", "set=true"}},
	} {
		t.Run(tc.action, func(t *testing.T) {
			host := rackHost("mini-01", func(h *infrav1.RackHost) {
				h.Annotations = map[string]string{PowerActionAnnotation: tc.action}
			})
			driver := &stubPowerDriver{on: true}
			r := newRackHostReconciler(t, driver, host)

			reconcileHost(t, r, "mini-01")

			if got := driver.recorded(); len(got) != len(tc.want) {
				t.Fatalf("outlet calls = %v, want %v", got, tc.want)
			}
			got := readHost(t, r, "mini-01")
			if _, still := got.Annotations[PowerActionAnnotation]; still {
				t.Fatal("annotation not cleared; the action would re-fire on every reconcile")
			}
			if got.Status.LastPowerAction != tc.action {
				t.Fatalf("LastPowerAction = %q, want %q", got.Status.LastPowerAction, tc.action)
			}
			if got.Status.LastPowerActionTime == nil {
				t.Fatal("LastPowerActionTime unset; a host that rebooted would look spontaneous")
			}
		})
	}
}

// A failed action must still clear its annotation. Left in place, a failing
// `cycle` power-cycles the box on every reconcile for as long as nobody notices.
func TestFailedPowerActionStillClearsItsAnnotation(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Annotations = map[string]string{PowerActionAnnotation: "cycle"}
	})
	r := newRackHostReconciler(t, &stubPowerDriver{on: true, err: errors.New("plug unreachable")}, host)

	reconcileHost(t, r, "mini-01")

	if _, still := readHost(t, r, "mini-01").Annotations[PowerActionAnnotation]; still {
		t.Fatal("a failing cycle stayed annotated; it would repeat every reconcile")
	}
}

func TestInvalidPowerActionIsRejectedNotGuessed(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Annotations = map[string]string{PowerActionAnnotation: "reboot"}
	})
	driver := &stubPowerDriver{on: true}
	r := newRackHostReconciler(t, driver, host)

	reconcileHost(t, r, "mini-01")

	if got := driver.recorded(); len(got) != 0 {
		t.Fatalf("an unrecognised action touched the outlet: %v", got)
	}
}

// Cutting power to a host that is Ready and schedulable kills running work.
// The normal reason to reach for this is a wedged host, and a wedged host is
// not the one still taking jobs, so it needs an explicit override.
func TestPowerCutIsRefusedForAServingNode(t *testing.T) {
	for _, action := range []string{"off", "cycle"} {
		t.Run(action, func(t *testing.T) {
			host := rackHost("mini-01", func(h *infrav1.RackHost) {
				h.Status.ClaimedBy = "ber1-0"
				h.Annotations = map[string]string{PowerActionAnnotation: action}
			})
			driver := &stubPowerDriver{on: true}
			r := newRackHostReconciler(t, driver, host, rackMachine("ber1-0"), node("ber1-0", true))

			reconcileHost(t, r, "mini-01")

			if got := driver.recorded(); len(got) != 0 {
				t.Fatalf("%s cut power to a serving node without force: %v", action, got)
			}
			if _, still := readHost(t, r, "mini-01").Annotations[PowerActionAnnotation]; still {
				t.Fatal("refused action stayed annotated; it would be re-evaluated forever")
			}
		})
	}
}

// `on` never cuts power, so it needs no override: refusing it would just be
// friction on the action that recovers a host someone switched off.
func TestPowerOnIsAllowedForAServingNode(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Status.ClaimedBy = "ber1-0"
		h.Annotations = map[string]string{PowerActionAnnotation: "on"}
	})
	driver := &stubPowerDriver{}
	r := newRackHostReconciler(t, driver, host, rackMachine("ber1-0"), node("ber1-0", true))

	reconcileHost(t, r, "mini-01")

	if got := driver.recorded(); len(got) != 1 || got[0] != "set=true" {
		t.Fatalf("outlet calls = %v, want a single power-on", got)
	}
}

func TestPowerCutIsAllowedWhenTheNodeIsNotServing(t *testing.T) {
	for _, tc := range []struct {
		name string
		objs []runtime.Object
	}{
		{"no Node at all", nil},
		{"Node NotReady", []runtime.Object{node("ber1-0", false)}},
		// Cordoning is how an operator says they are about to take the box
		// away; requiring force after that is friction with no safety left.
		{"Node cordoned", []runtime.Object{node("ber1-0", true, func(n *corev1.Node) { n.Spec.Unschedulable = true })}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			host := rackHost("mini-01", func(h *infrav1.RackHost) {
				h.Status.ClaimedBy = "ber1-0"
				h.Annotations = map[string]string{PowerActionAnnotation: "cycle"}
			})
			driver := &stubPowerDriver{on: true}
			objs := append([]runtime.Object{host, rackMachine("ber1-0")}, tc.objs...)
			r := newRackHostReconciler(t, driver, objs...)

			reconcileHost(t, r, "mini-01")

			if got := driver.recorded(); len(got) != 2 {
				t.Fatalf("outlet calls = %v, want an off then an on", got)
			}
		})
	}
}

func TestForcedPowerCutOverridesTheServingGuard(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Status.ClaimedBy = "ber1-0"
		h.Annotations = map[string]string{
			PowerActionAnnotation:      "cycle",
			PowerActionForceAnnotation: "true",
		}
	})
	driver := &stubPowerDriver{on: true}
	r := newRackHostReconciler(t, driver, host, rackMachine("ber1-0"), node("ber1-0", true))

	reconcileHost(t, r, "mini-01")

	if got := driver.recorded(); len(got) != 2 {
		t.Fatalf("forced cycle did not run: %v", got)
	}
	got := readHost(t, r, "mini-01")
	// The force flag is one-shot too. Left behind, the next ordinary action
	// would silently inherit an override nobody meant to grant it.
	if _, still := got.Annotations[PowerActionForceAnnotation]; still {
		t.Fatal("force annotation not cleared; a later action would inherit the override")
	}
}

// --- watch mapping ----------------------------------------------------------

func TestRackHostForStaticMachineMapsOnlyBoundMachines(t *testing.T) {
	bound := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) { m.Status.RackHost = "mini-01" })
	if reqs := rackHostForStaticMachine(context.Background(), bound); len(reqs) != 1 || reqs[0].Name != "mini-01" {
		t.Fatalf("bound machine mapped to %v, want mini-01", reqs)
	}
	if reqs := rackHostForStaticMachine(context.Background(), rackMachine("ber1-1")); len(reqs) != 0 {
		t.Fatalf("hostless machine mapped to %v, want nothing", reqs)
	}
}

// --- helpers ----------------------------------------------------------------

func conditionOf(host *infrav1.RackHost, t clusterv1.ConditionType) *clusterv1.Condition {
	for i := range host.Status.Conditions {
		if host.Status.Conditions[i].Type == t {
			return &host.Status.Conditions[i]
		}
	}
	return nil
}

type erroringDriver struct{}

func (erroringDriver) State(context.Context, power.Outlet) (power.State, error) {
	return power.StateUnknown, errors.New("dial 192.168.0.50: i/o timeout")
}
func (erroringDriver) Set(context.Context, power.Outlet, bool) error {
	return errors.New("dial 192.168.0.50: i/o timeout")
}

type credentialRecordingDriver struct {
	username, password string
}

func (d *credentialRecordingDriver) State(_ context.Context, o power.Outlet) (power.State, error) {
	d.username, d.password = o.Username, o.Password
	return power.StateOn, nil
}
func (d *credentialRecordingDriver) Set(_ context.Context, o power.Outlet, _ bool) error {
	d.username, d.password = o.Username, o.Password
	return nil
}

// --- quarantine expiry ------------------------------------------------------

// A quarantine that never expires is a physical box removed from the pool that
// nobody present can put back: clearing it needs write access to
// rackhosts/status, which the operator's ClusterRole has and a human reaching
// the cluster through the kubectl gateway does not. Discovered the hard way on
// 2026-09-09, when the BER1 prototype quarantined itself over a bootstrap bug
// and the patch to release it came back Forbidden.
func TestQuarantineExpiresAfterTheCooldown(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Status.Quarantined = true
		h.Status.QuarantineReason = "bootstrap failed 8 times"
		h.Status.QuarantinedAt = &metav1.Time{Time: time.Now().Add(-31 * time.Minute)}
	})
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, host)

	reconcileHost(t, r, "mini-01")

	got := readHost(t, r, "mini-01")
	if got.Status.Quarantined {
		t.Fatal("still quarantined past the cooldown; the host is stranded out of the pool")
	}
	if got.Status.QuarantineReason != "" || got.Status.QuarantinedAt != nil {
		t.Fatalf("quarantine bookkeeping survived the release: %+v", got.Status)
	}
}

// Inside the window it must hold, or the ladder degrades to retrying a broken
// host on every reconcile instead of once per interval.
func TestQuarantineHoldsInsideTheCooldown(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Status.Quarantined = true
		h.Status.QuarantinedAt = &metav1.Time{Time: time.Now().Add(-2 * time.Minute)}
	})
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, host)

	reconcileHost(t, r, "mini-01")

	if !readHost(t, r, "mini-01").Status.Quarantined {
		t.Fatal("quarantine lifted early; a broken host would be retried every reconcile")
	}
}

// A host quarantined before the timestamp field existed carries none. Releasing
// those on sight is the point: the field was added because there was no other
// way to get them back.
func TestQuarantineWithoutATimestampIsReleased(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Status.Quarantined = true
		h.Status.QuarantineReason = "quarantined by an older operator"
	})
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, host)

	reconcileHost(t, r, "mini-01")

	if readHost(t, r, "mini-01").Status.Quarantined {
		t.Fatal("a timestampless quarantine stayed forever, which is exactly the state this field exists to end")
	}
}

// An operator who has another way to clear quarantines can opt out of the
// expiry entirely.
func TestNegativeCooldownMakesQuarantinePermanent(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Status.Quarantined = true
		h.Status.QuarantinedAt = &metav1.Time{Time: time.Now().Add(-99 * time.Hour)}
	})
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, host)
	r.QuarantineRetryAfter = -1

	reconcileHost(t, r, "mini-01")

	if !readHost(t, r, "mini-01").Status.Quarantined {
		t.Fatal("expiry ran despite being disabled")
	}
}

// An expired quarantine must actually let a machine claim the host again;
// clearing the flag is only half of it.
func TestExpiredQuarantineMakesTheHostClaimableAgain(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Status.Quarantined = true
		h.Status.QuarantinedAt = &metav1.Time{Time: time.Now().Add(-31 * time.Minute)}
	})
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, host)
	reconcileHost(t, r, "mini-01")

	released := readHost(t, r, "mini-01")
	candidates, _ := selectClaimableHosts([]infrav1.RackHost{*released}, testPool, "ber1-0")
	if len(candidates) != 1 {
		t.Fatalf("released host is still not claimable: %d candidates", len(candidates))
	}
}
