package macos

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
)

func loginAttempts(h *pduHarness) int {
	h.card.Mu.Lock()
	defer h.card.Mu.Unlock()
	return h.card.LoginAttempts
}

func (h *pduHarness) clock() *time.Time {
	now := time.Now()
	h.r.loginBackoff.now = func() time.Time { return now }
	return &now
}

// A card may block an account after repeated failed logins, so a refused
// login is retried later and later, not every minute.
func TestRackPDUBacksOffRefusedControllerLogins(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()
	h.assertAdopted()
	h.card.Mu.Lock()
	for _, a := range h.card.Accounts {
		if a.Name == "tuist-controller" {
			a.Password = "Somebody-else1"
		}
	}
	h.card.Mu.Unlock()
	h.card.Expire()
	now := h.clock()

	res := h.reconcile()
	if reason := conditions.GetReason(h.pdu(), clusterv1.ReadyCondition); reason != "ControllerLoginFailed" || res.RequeueAfter != time.Minute {
		t.Fatalf("first refusal: Ready reason %q, requeue %s; want ControllerLoginFailed after 1m", reason, res.RequeueAfter)
	}

	attempts := loginAttempts(h)
	res = h.reconcile()
	if loginAttempts(h) != attempts || res.RequeueAfter <= 0 || res.RequeueAfter > time.Minute {
		t.Fatalf("a reconcile inside the backoff tried %d logins, requeue %s", loginAttempts(h)-attempts, res.RequeueAfter)
	}

	*now = now.Add(time.Minute)
	res = h.reconcile()
	if loginAttempts(h) == attempts || res.RequeueAfter != 2*time.Minute {
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
	pdu := h.pdu()
	pdu.Generation = 2
	if err := h.r.Update(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}
	h.reconcile()
	h.assertAdopted()
}

func TestRackPDUBacksOffARefusedAdministratorLogin(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.card.Mu.Lock()
	h.card.Accounts["0"].Password, h.card.Accounts["0"].PasswordExpired = "Somebody-else1", false
	h.card.Mu.Unlock()
	now := h.clock()

	res := h.reconcile()
	if reason := conditions.GetReason(h.pdu(), RackPDUAdoptedCondition); reason != "AdminLoginRefused" || res.RequeueAfter != time.Minute {
		t.Fatalf("Adopted reason %q, requeue %s", reason, res.RequeueAfter)
	}
	attempts := loginAttempts(h)
	h.reconcile()
	if loginAttempts(h) != attempts {
		t.Fatalf("retried the administrator's logins %d times inside the backoff", loginAttempts(h)-attempts)
	}
	*now = now.Add(time.Minute)
	if res = h.reconcile(); res.RequeueAfter != 2*time.Minute || loginAttempts(h) == attempts {
		t.Fatalf("after the backoff: requeue %s, want the logins tried again and 2m next", res.RequeueAfter)
	}

	// An annotation starts over.
	pdu := h.pdu()
	pdu.Annotations = map[string]string{"tuist.dev/retry": "now"}
	if err := h.r.Update(context.Background(), pdu); err != nil {
		t.Fatal(err)
	}
	if res = h.reconcile(); res.RequeueAfter != time.Minute {
		t.Fatalf("after an annotation: requeue %s, want the backoff restarted at 1m", res.RequeueAfter)
	}
}

func TestRackPDUReportsABlockedAccount(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()
	h.card.Mu.Lock()
	for _, a := range h.card.Accounts {
		if a.Name == "tuist-controller" {
			a.Locked = true
		}
	}
	h.card.Mu.Unlock()
	h.card.Expire()

	h.reconcile()

	cond := conditions.Get(h.pdu(), clusterv1.ReadyCondition)
	if cond == nil || cond.Status == corev1.ConditionTrue || cond.Reason != "AccountBlocked" {
		t.Fatalf("Ready = %+v, want False/AccountBlocked", cond)
	}
}
