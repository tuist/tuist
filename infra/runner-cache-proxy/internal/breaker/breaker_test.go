package breaker

import (
	"testing"
	"time"
)

func TestUnhealthyGate(t *testing.T) {
	b := New(3, time.Minute)
	if !b.Allow() {
		t.Fatal("should start closed and healthy")
	}
	b.SetHealthy(false)
	if b.Allow() {
		t.Fatal("unhealthy gate should block routing to the gateway")
	}
	b.SetHealthy(true)
	if !b.Allow() {
		t.Fatal("restored health should allow routing")
	}
}

func TestLiveFailureTrip(t *testing.T) {
	now := time.Unix(0, 0)
	b := New(3, time.Minute)
	b.now = func() time.Time { return now }

	b.RecordFailure()
	b.RecordFailure()
	if !b.Allow() {
		t.Fatal("should not trip before threshold")
	}
	b.RecordFailure()
	if b.Allow() {
		t.Fatal("should trip at threshold")
	}
	now = now.Add(2 * time.Minute)
	if !b.Allow() {
		t.Fatal("should admit a probe after cooldown")
	}
}

func TestSuccessResets(t *testing.T) {
	b := New(2, time.Minute)
	b.RecordFailure()
	b.RecordSuccess()
	b.RecordFailure()
	if !b.Allow() {
		t.Fatal("success should have reset the live failure count")
	}
}

func TestState(t *testing.T) {
	b := New(1, time.Minute)
	if b.State() != Closed {
		t.Fatal("fresh breaker should be closed")
	}
	b.SetHealthy(false)
	if b.State() != Open {
		t.Fatal("unhealthy breaker should report open")
	}
}
