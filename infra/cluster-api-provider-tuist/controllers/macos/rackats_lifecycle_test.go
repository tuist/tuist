package macos

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

func (h *atsHarness) loginAttempts() int {
	h.card.Mu.Lock()
	defer h.card.Mu.Unlock()
	return h.card.LoginAttempts
}

func (h *atsHarness) clock() *time.Time {
	now := time.Now()
	h.r.loginBackoff.now = func() time.Time { return now }
	h.r.adminBackoff.now = func() time.Time { return now }
	return &now
}

// A card may block an account after repeated failed logins, so a refused
// login is retried later and later, not every minute.
func TestRackATSBacksOffRefusedControllerLogins(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	h.assertAdopted(1)
	h.card.Mu.Lock()
	for _, a := range h.card.Accounts {
		if a.Name == "tuist-controller" {
			a.Password = "Somebody-else1"
		}
	}
	h.card.Mu.Unlock()
	h.card.Expire()
	// The administrator too, or adopting again would remake the account.
	setAccountPassword(h.card, "admin", "Somebody-else2")
	now := h.clock()

	res := h.reconcile()
	if reason := conditions.GetReason(h.ats(), clusterv1.ReadyCondition); reason != "ControllerLoginFailed" || res.RequeueAfter != time.Minute {
		t.Fatalf("first refusal: Ready reason %q, requeue %s; want ControllerLoginFailed after 1m", reason, res.RequeueAfter)
	}
	attempts := h.loginAttempts()
	res = h.reconcile()
	if h.loginAttempts() != attempts || res.RequeueAfter <= 0 || res.RequeueAfter > time.Minute {
		t.Fatalf("a reconcile inside the backoff tried %d logins, requeue %s", h.loginAttempts()-attempts, res.RequeueAfter)
	}
	*now = now.Add(time.Minute)
	res = h.reconcile()
	if h.loginAttempts() == attempts || res.RequeueAfter != 2*time.Minute {
		t.Fatalf("after the backoff: requeue %s, want the login tried again and 2m next", res.RequeueAfter)
	}
	for range 10 {
		*now = now.Add(res.RequeueAfter)
		res = h.reconcile()
	}
	if res.RequeueAfter != time.Hour {
		t.Fatalf("requeue %s after many refusals, want the 1h cap", res.RequeueAfter)
	}

	// A new generation starts over, and adopting makes the account again.
	setAccountPassword(h.card, "admin", atsPasswords().Admin)
	h.update(func(a *infrav1.RackATS) { a.Generation = 2 })
	h.reconcile()
	h.assertAdopted(1)
}

func TestRackATSBacksOffARefusedAdministratorLogin(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.card.Mu.Lock()
	h.card.Accounts["0"].Password, h.card.Accounts["0"].PasswordExpired = "Somebody-else1", false
	h.card.Mu.Unlock()
	now := h.clock()

	res := h.reconcile()
	if reason := conditions.GetReason(h.ats(), RackCardAdoptedCondition); reason != "AdminLoginRefused" || res.RequeueAfter != time.Minute {
		t.Fatalf("Adopted reason %q, requeue %s", reason, res.RequeueAfter)
	}
	attempts := h.loginAttempts()
	h.reconcile()
	if h.loginAttempts() != attempts {
		t.Fatalf("retried the administrator's logins %d times inside the backoff", h.loginAttempts()-attempts)
	}
	*now = now.Add(time.Minute)
	if res = h.reconcile(); res.RequeueAfter != 2*time.Minute || h.loginAttempts() == attempts {
		t.Fatalf("after the backoff: requeue %s, want the logins tried again and 2m next", res.RequeueAfter)
	}

	// An annotation starts over.
	h.update(func(a *infrav1.RackATS) { a.Annotations = map[string]string{"tuist.dev/retry": "now"} })
	if res = h.reconcile(); res.RequeueAfter != time.Minute {
		t.Fatalf("after an annotation: requeue %s, want the backoff restarted at 1m", res.RequeueAfter)
	}
}

func TestRackATSReportsABlockedAccount(t *testing.T) {
	for _, who := range []string{"tuist-controller", "admin"} {
		t.Run(who, func(t *testing.T) {
			h := newATSHarness(t, rackATS())
			if who == "tuist-controller" {
				h.reconcile()
			}
			h.card.Mu.Lock()
			for _, a := range h.card.Accounts {
				if a.Name == who {
					a.Locked = true
				}
			}
			h.card.Mu.Unlock()
			h.card.Expire()
			h.clock()

			res := h.reconcile()

			cond := h.condition(clusterv1.ReadyCondition)
			if cond == nil || cond.Status == corev1.ConditionTrue || cond.Reason != "AccountBlocked" {
				t.Fatalf("Ready = %+v, want False/AccountBlocked", cond)
			}
			if res.RequeueAfter != time.Minute {
				t.Fatalf("requeue %s, want the backoff's first minute", res.RequeueAfter)
			}
			if who == "admin" {
				if reason := conditions.GetReason(h.ats(), RackCardAdoptedCondition); reason != "AccountBlocked" {
					t.Fatalf("Adopted reason %q, want AccountBlocked", reason)
				}
			}
		})
	}
}

// A transfer switch the controller stops managing, or that is deleted, gets
// its session on the card logged out, so the card's one session for the
// account is free.
func TestRackATSMadeStandaloneLogsTheControllerOut(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	if n := h.card.OpenSessions(); n != 1 {
		t.Fatalf("%d sessions after adoption, want the controller's", n)
	}
	h.update(func(a *infrav1.RackATS) { a.Spec.ManagedBy = infrav1.RackCardManagedByStandalone })

	h.reconcile()

	if n := h.card.OpenSessions(); n != 0 {
		t.Fatalf("%d sessions left open on a standalone transfer switch", n)
	}
}

func TestRackATSDeletedLogsTheControllerOutAndLetsGo(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	ats := h.ats()
	if len(ats.Finalizers) != 1 || ats.Finalizers[0] != RackATSFinalizer {
		t.Fatalf("finalizers = %v, want %s held without an egress", ats.Finalizers, RackATSFinalizer)
	}

	if err := h.r.Delete(context.Background(), ats); err != nil {
		t.Fatal(err)
	}
	h.reconcile()

	if n := h.card.OpenSessions(); n != 0 {
		t.Fatalf("%d sessions left open for a deleted transfer switch", n)
	}
	err := h.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: testATS}, &infrav1.RackATS{})
	if !apierrors.IsNotFound(err) {
		t.Fatalf("RackATS after delete: %v", err)
	}
}

// An adopted switch whose administrator login is refused for a new
// generation is still observed; only the administrator's logins back off.
func TestRackATSKeepsObservingWhileTheAdministratorBacksOff(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	h.card.Mu.Lock()
	h.card.Accounts["0"].Password = "Somebody-else1"
	h.card.Mu.Unlock()
	h.update(func(a *infrav1.RackATS) { a.Generation = 2 })
	h.clock()

	h.reconcile()
	attempts := h.loginAttempts()
	res := h.reconcile()

	ats := h.ats()
	if !conditions.IsTrue(ats, clusterv1.ReadyCondition) || ats.Status.LastObserved == nil || res.RequeueAfter != rackATSObserveInterval {
		t.Fatalf("Ready = %+v, requeue %s: observation stopped", conditions.Get(ats, clusterv1.ReadyCondition), res.RequeueAfter)
	}
	if cond := conditions.Get(ats, RackCardConvergedCondition); cond == nil || cond.Status != corev1.ConditionFalse {
		t.Fatalf("Converged = %+v, want False for the unconverged generation", cond)
	}
	if h.loginAttempts() != attempts {
		t.Fatalf("tried %d logins inside the administrator's backoff", h.loginAttempts()-attempts)
	}
}

// An object an earlier build held with the egress-only finalizer is moved to
// the current one, and still let go when deleted with only the old one.
func TestRackATSLegacyFinalizer(t *testing.T) {
	h := newATSHarness(t, rackATS(func(a *infrav1.RackATS) { a.Finalizers = []string{legacyRackATSFinalizer} }))
	h.reconcile()
	if f := h.ats().Finalizers; len(f) != 1 || f[0] != RackATSFinalizer {
		t.Fatalf("finalizers = %v, want only %s", f, RackATSFinalizer)
	}

	h2 := newATSHarness(t, rackATS(func(a *infrav1.RackATS) { a.Finalizers = []string{legacyRackATSFinalizer} }))
	if err := h2.r.Delete(context.Background(), h2.ats()); err != nil {
		t.Fatal(err)
	}
	h2.reconcile()
	err := h2.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: testATS}, &infrav1.RackATS{})
	if !apierrors.IsNotFound(err) {
		t.Fatalf("RackATS held only by the old finalizer after delete: %v", err)
	}
}
