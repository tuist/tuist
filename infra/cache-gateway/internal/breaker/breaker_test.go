package breaker

import (
	"testing"
	"time"
)

func TestTripsAfterConsecutiveFailures(t *testing.T) {
	now := time.Unix(0, 0)
	b := New(3, time.Minute)
	b.now = func() time.Time { return now }

	if !b.Allow() {
		t.Fatal("breaker should start closed")
	}
	b.RecordFailure()
	b.RecordFailure()
	if !b.Allow() {
		t.Fatal("breaker tripped before threshold")
	}
	b.RecordFailure() // third consecutive
	if b.Allow() {
		t.Fatal("breaker did not open at threshold")
	}
	if b.State() != Open {
		t.Fatalf("state = %v want open", b.State())
	}
}

func TestSuccessResetsCounter(t *testing.T) {
	now := time.Unix(0, 0)
	b := New(3, time.Minute)
	b.now = func() time.Time { return now }

	b.RecordFailure()
	b.RecordFailure()
	b.RecordSuccess()
	b.RecordFailure()
	b.RecordFailure()
	if !b.Allow() {
		t.Fatal("success should have reset the consecutive-failure count")
	}
}

func TestHalfOpenRecovery(t *testing.T) {
	now := time.Unix(0, 0)
	b := New(1, time.Minute)
	b.now = func() time.Time { return now }

	b.RecordFailure() // opens immediately (threshold 1)
	if b.Allow() {
		t.Fatal("should be open")
	}
	now = now.Add(2 * time.Minute) // past cooldown
	if !b.Allow() {
		t.Fatal("should admit a half-open probe after cooldown")
	}
	if b.State() != HalfOpen {
		t.Fatalf("state = %v want half_open", b.State())
	}
	b.RecordSuccess()
	if !b.Allow() || b.State() != Closed {
		t.Fatal("successful probe should close the breaker")
	}
}

func TestHalfOpenProbeFailureReopens(t *testing.T) {
	now := time.Unix(0, 0)
	b := New(1, time.Minute)
	b.now = func() time.Time { return now }

	b.RecordFailure()
	now = now.Add(2 * time.Minute)
	_ = b.Allow() // half-open probe admitted
	b.RecordFailure()
	if b.State() != Open {
		t.Fatalf("failed probe should reopen, state=%v", b.State())
	}
	if b.Allow() {
		t.Fatal("should be open again immediately after failed probe")
	}
}
