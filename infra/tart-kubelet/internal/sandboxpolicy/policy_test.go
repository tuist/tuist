package sandboxpolicy

import (
	"testing"
	"time"
)

func TestCIAdmissionAndWarmGrace(t *testing.T) {
	now := time.Date(2026, 10, 27, 12, 0, 0, 0, time.UTC)
	base := Observation{At: now, Host: "mac-a", OwnerHost: "mac-a", Generation: "boot-1", OwnerGeneration: "boot-1", CIKnown: true, Healthy: true, DiskReady: true, Capacity: Resources{2, 16, 49152}, Request: Resources{1, 8, 8192}, Headroom: Resources{1, 8, 24576}, IdleSince: now.Add(-10 * time.Second)}
	for _, tt := range []struct {
		name, want string
		change     func(*Observation)
	}{
		{"fits", "would_admit", func(*Observation) {}},
		{"queued CI", "wait_for_ci_capacity", func(o *Observation) { o.QueuedCI = 1 }},
		{"stale signals", "wait_for_ci_capacity", func(o *Observation) { o.At = now.Add(-16 * time.Second) }},
		{"unknown demand", "wait_for_ci_capacity", func(o *Observation) { o.CIKnown = false }},
		{"future signals", "wait_for_ci_capacity", func(o *Observation) { o.At = now.Add(2 * time.Second) }},
		{"wrong host", "wait_for_ci_capacity", func(o *Observation) { o.Host = "mac-b" }},
		{"host reboot", "wait_for_ci_capacity", func(o *Observation) { o.Generation = "boot-2" }},
		{"CI reservation", "wait_for_ci_capacity", func(o *Observation) { o.Reserved = true }},
		{"disk pressure", "wait_for_ci_capacity", func(o *Observation) { o.DiskReady = false }},
		{"memory fits but slots full", "wait_for_ci_capacity", func(o *Observation) { o.Committed = Resources{2, 4, 4096}; o.Headroom = Resources{} }},
		{"CPU full", "wait_for_ci_capacity", func(o *Observation) { o.Committed = Resources{1, 16, 4096}; o.Headroom = Resources{} }},
		{"memory full", "wait_for_ci_capacity", func(o *Observation) { o.Committed = Resources{1, 4, 45000}; o.Headroom = Resources{} }},
		{"CI teardown still charged", "wait_for_ci_capacity", func(o *Observation) { o.Committed = Resources{1, 8, 24576} }},
		{"warm grace", "pause_resident", func(o *Observation) { o.Resident = true; o.Committed = o.Request }},
		{"queued CI bypasses grace", "evict", func(o *Observation) { o.Resident = true; o.Committed = o.Request; o.QueuedCI = 1 }},
		{"stale demand bypasses grace", "evict", func(o *Observation) { o.Resident = true; o.Committed = o.Request; o.CIKnown = false }},
		{"expired grace", "evict", func(o *Observation) {
			o.Resident = true
			o.Committed = o.Request
			o.IdleSince = now.Add(-30 * time.Second)
		}},
		{"missing resident charge", "evict", func(o *Observation) { o.Resident = true }},
		{"active turn protected", "keep_running", func(o *Observation) { o.Active = true; o.CIKnown = false; o.QueuedCI = 10 }},
	} {
		t.Run(tt.name, func(t *testing.T) {
			o := base
			tt.change(&o)
			d := Evaluate(now, DefaultWarmGrace, o)
			if d.Action != tt.want || !d.Shadow {
				t.Fatalf("got %+v, want %s in shadow mode", d, tt.want)
			}
		})
	}
	o := base
	o.Resident = true
	o.Committed = o.Request
	o.IdleSince = now.Add(-61 * time.Second)
	if got := Evaluate(now, time.Hour, o); got.Action != "evict" {
		t.Fatalf("unbounded grace: %+v", got)
	}
}

func TestResidentPauseRetainsFullCICharge(t *testing.T) {
	now := time.Date(2026, 10, 28, 12, 0, 0, 0, time.UTC)
	base := Observation{At: now, Host: "mac-a", OwnerHost: "mac-a", Generation: "boot-1", OwnerGeneration: "boot-1",
		CIKnown: true, Healthy: true, DiskReady: true, Capacity: Resources{2, 16, 32768},
		Request: Resources{1, 8, 16384}, Committed: Resources{1, 8, 16384}, Headroom: Resources{1, 8, 16384},
		Resident: true, Paused: true, IdleSince: now.Add(-time.Second)}
	for _, tt := range []struct {
		name, action, reason string
		change               func(*Observation)
	}{
		{"retain spare", "keep_paused", "ci_headroom_available", func(*Observation) {}},
		{"CI arrives", "evict", "ci_queued_or_invalid", func(o *Observation) { o.QueuedCI = 1 }},
		{"CI memory headroom grows", "evict", "ci_headroom", func(o *Observation) { o.Headroom.MemoryMB++ }},
		{"CI slot headroom grows", "evict", "ci_headroom", func(o *Observation) { o.Headroom.Slots++ }},
		{"CI CPU headroom grows", "evict", "ci_headroom", func(o *Observation) { o.Headroom.VCPUs++ }},
		{"lost demand signal", "evict", "stale_or_unknown_demand", func(o *Observation) { o.CIKnown = false }},
		{"paused memory undercharged", "evict", "invalid_resident_charge", func(o *Observation) { o.Committed.MemoryMB-- }},
		{"paused slot undercharged", "evict", "invalid_resident_charge", func(o *Observation) { o.Committed.Slots = 0 }},
		{"paused CPU undercharged", "evict", "invalid_resident_charge", func(o *Observation) { o.Committed.VCPUs-- }},
		{"expired retention", "evict", "idle_grace_expired", func(o *Observation) { o.IdleSince = now.Add(-DefaultWarmGrace) }},
		{"paused without process", "reconcile", "invalid_paused_state", func(o *Observation) { o.Resident = false }},
		{"active but paused", "reconcile", "invalid_paused_state", func(o *Observation) { o.Active = true }},
		{"resident on another host", "reconcile", "owner_mismatch", func(o *Observation) { o.OwnerHost = "mac-b" }},
		{"resident before host reboot", "reconcile", "owner_mismatch", func(o *Observation) { o.OwnerGeneration = "boot-0" }},
		{"lost demand and ownership", "reconcile", "owner_mismatch", func(o *Observation) { o.OwnerGeneration = "boot-0"; o.CIKnown = false }},
	} {
		t.Run(tt.name, func(t *testing.T) {
			o := base
			tt.change(&o)
			got := Evaluate(now, DefaultWarmGrace, o)
			if got.Action != tt.action || got.Reason != tt.reason || !got.Shadow {
				t.Fatalf("got %+v, want %s/%s in shadow mode", got, tt.action, tt.reason)
			}
		})
	}
}
