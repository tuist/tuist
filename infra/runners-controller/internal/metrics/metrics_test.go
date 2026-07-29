package metrics

import (
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestWarmDeficit(t *testing.T) {
	tests := []struct {
		name                    string
		load, floor, tgt, alloc int32
		want                    int32
	}{
		{
			// Fully funded: allocated covers load + floor, no deficit.
			name: "fully funded", load: 17, floor: 30, tgt: 60, alloc: 60, want: 0,
		},
		{
			// Squeezed to load + partial floor: only 9 of the 30-pod
			// floor funded (the June 2026 linux-2vcpu-8gb incident shape).
			name: "floor reaped to load+9", load: 17, floor: 30, tgt: 60, alloc: 26, want: 21,
		},
		{
			// Allocated below even raw load (shouldn't happen — load is
			// inviolable — but the metric must never go negative).
			name: "allocated below load clamps at floor want", load: 17, floor: 30, tgt: 60, alloc: 10, want: 30,
		},
		{
			// Headroom (p95 buffer above the floor) is NOT counted: target
			// 60 but only load+floor = 47 is the warm guarantee, and that's
			// funded, so deficit is 0 even though allocated < target.
			name: "headroom reaped is not a deficit", load: 17, floor: 30, tgt: 60, alloc: 47, want: 0,
		},
		{
			// No floor configured: nothing speculative to reap.
			name: "zero floor", load: 5, floor: 0, tgt: 5, alloc: 5, want: 0,
		},
		{
			// want is capped at target: a floor larger than the target
			// can't manufacture a deficit beyond what was asked for.
			name: "want capped at target", load: 0, floor: 30, tgt: 10, alloc: 4, want: 6,
		},
		{
			// Defensive: negative inputs are clamped to 0.
			name: "negative load clamped", load: -3, floor: 5, tgt: 5, alloc: 5, want: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := warmDeficit(tt.load, tt.floor, tt.tgt, tt.alloc); got != tt.want {
				t.Errorf("warmDeficit(%d,%d,%d,%d) = %d, want %d",
					tt.load, tt.floor, tt.tgt, tt.alloc, got, tt.want)
			}
		})
	}
}

func TestClearAutoscalerLeavesRunnerPoolPhaseReplicas(t *testing.T) {
	const pool = "p"

	target.Reset()
	allocated.Reset()
	warmDeficitReplicas.Reset()
	minWarmFloor.Reset()
	phaseReplicas.Reset()

	RecordAllocation(pool, 1, 2, 3, 3)
	RecordPodPhases(pool, 4, 5, 6)

	ClearAutoscaler(pool)

	if got := testutil.ToFloat64(phaseReplicas.WithLabelValues(pool, "Pending")); got != 4 {
		t.Fatalf("Pending phase replicas after ClearAutoscaler = %v, want 4", got)
	}
	if got := testutil.ToFloat64(phaseReplicas.WithLabelValues(pool, "Running")); got != 5 {
		t.Fatalf("Running phase replicas after ClearAutoscaler = %v, want 5", got)
	}
	if got := testutil.ToFloat64(phaseReplicas.WithLabelValues(pool, "Unknown")); got != 6 {
		t.Fatalf("Unknown phase replicas after ClearAutoscaler = %v, want 6", got)
	}
}

func TestClearDropsRunnerPoolPhaseReplicas(t *testing.T) {
	const pool = "p"

	phaseReplicas.Reset()

	RecordPodPhases(pool, 4, 5, 6)
	Clear(pool)

	if got := testutil.CollectAndCount(phaseReplicas); got != 0 {
		t.Fatalf("phase replica metric count after Clear = %d, want 0", got)
	}
}

func TestRecordOldestPendingPodAge(t *testing.T) {
	const pool = "p"

	oldestPendingPodAge.Reset()

	RecordOldestPendingPodAge(pool, 90*time.Second)
	if got := testutil.ToFloat64(oldestPendingPodAge.WithLabelValues(pool)); got != 90 {
		t.Fatalf("oldest pending pod age = %v, want 90", got)
	}

	// Drains rather than holding its last non-zero sample: a pool whose
	// Pods have all booted must not keep reporting the old peak.
	RecordOldestPendingPodAge(pool, 0)
	if got := testutil.ToFloat64(oldestPendingPodAge.WithLabelValues(pool)); got != 0 {
		t.Fatalf("oldest pending pod age after drain = %v, want 0", got)
	}
}

// A clock skewed backwards must not publish a negative age, which would
// plot below every threshold and read as a healthy pool.
func TestRecordOldestPendingPodAgeClampsNegative(t *testing.T) {
	const pool = "p"

	oldestPendingPodAge.Reset()

	RecordOldestPendingPodAge(pool, -5*time.Second)
	if got := testutil.ToFloat64(oldestPendingPodAge.WithLabelValues(pool)); got != 0 {
		t.Fatalf("negative age = %v, want clamped to 0", got)
	}
}

func TestRecordProvisioningSafetyMetrics(t *testing.T) {
	const pool = "linux"
	pendingProvisioningPods.Reset()
	admissionBlockedTotal.Reset()
	podStartTimeoutsTotal.Reset()
	fleetReadyNodes.Reset()
	fleetFilteredNodes.Reset()

	RecordPendingProvisioningPods(pool, 3)
	RecordAdmissionBlocked(pool, "fleet_cap")
	RecordPodStartTimeout(pool, "poller_not_started")
	RecordFleetNodes("runners-linux", "linux", 2, map[string]int{"not_ready": 1})

	if got := testutil.ToFloat64(pendingProvisioningPods.WithLabelValues(pool)); got != 3 {
		t.Fatalf("pending provisioning pods = %v, want 3", got)
	}
	if got := testutil.ToFloat64(admissionBlockedTotal.WithLabelValues(pool, "fleet_cap")); got != 1 {
		t.Fatalf("fleet-cap blocks = %v, want 1", got)
	}
	if got := testutil.ToFloat64(podStartTimeoutsTotal.WithLabelValues(pool, "poller_not_started")); got != 1 {
		t.Fatalf("pod start timeouts = %v, want 1", got)
	}
	if got := testutil.ToFloat64(fleetReadyNodes.WithLabelValues("runners-linux", "linux")); got != 2 {
		t.Fatalf("ready fleet nodes = %v, want 2", got)
	}
	if got := testutil.ToFloat64(fleetFilteredNodes.WithLabelValues("runners-linux", "linux", "not_ready")); got != 1 {
		t.Fatalf("not-ready fleet nodes = %v, want 1", got)
	}
	if got := testutil.ToFloat64(fleetFilteredNodes.WithLabelValues("runners-linux", "linux", "disk_pressure")); got != 0 {
		t.Fatalf("disk-pressure fleet nodes = %v, want 0", got)
	}
}

func TestClearDropsOldestPendingPodAge(t *testing.T) {
	const pool = "p"

	oldestPendingPodAge.Reset()

	RecordOldestPendingPodAge(pool, 30*time.Second)
	Clear(pool)

	if got := testutil.CollectAndCount(oldestPendingPodAge); got != 0 {
		t.Fatalf("oldest pending pod age count after Clear = %d, want 0", got)
	}
}

func TestRecordDemandPublishesSignalsUnsummed(t *testing.T) {
	const pool = "p"

	claimedJobs.Reset()
	queuedJobs.Reset()

	RecordDemand(pool, 3, 8)

	if got := testutil.ToFloat64(claimedJobs.WithLabelValues(pool)); got != 3 {
		t.Fatalf("claimed jobs = %v, want 3", got)
	}
	if got := testutil.ToFloat64(queuedJobs.WithLabelValues(pool)); got != 8 {
		t.Fatalf("queued jobs = %v, want 8", got)
	}

	// The whole point of the split: work draining normally moves a job
	// from queued to claimed and leaves claimed+queued flat, so only the
	// separate series show that dispatch is making progress.
	RecordDemand(pool, 4, 7)
	if got := testutil.ToFloat64(claimedJobs.WithLabelValues(pool)); got != 4 {
		t.Fatalf("claimed jobs after drain = %v, want 4", got)
	}
	if got := testutil.ToFloat64(queuedJobs.WithLabelValues(pool)); got != 7 {
		t.Fatalf("queued jobs after drain = %v, want 7", got)
	}
}

func TestRecordIdleReplicas(t *testing.T) {
	const pool = "p"

	idleReplicas.Reset()

	RecordIdleReplicas(pool, 8)
	if got := testutil.ToFloat64(idleReplicas.WithLabelValues(pool)); got != 8 {
		t.Fatalf("idle replicas = %v, want 8", got)
	}

	// Drains when the pool goes fully busy; a stale non-zero sample would
	// read as warm capacity sitting unused and fire starvation falsely.
	RecordIdleReplicas(pool, 0)
	if got := testutil.ToFloat64(idleReplicas.WithLabelValues(pool)); got != 0 {
		t.Fatalf("idle replicas after drain = %v, want 0", got)
	}
}

// Defensive: a scale-down decrement racing the count must not publish a
// negative gauge, which would plot below any starvation threshold.
func TestRecordIdleReplicasClampsNegative(t *testing.T) {
	const pool = "p"

	idleReplicas.Reset()

	RecordIdleReplicas(pool, -2)
	if got := testutil.ToFloat64(idleReplicas.WithLabelValues(pool)); got != 0 {
		t.Fatalf("negative idle replicas = %v, want clamped to 0", got)
	}
}

func TestClearDropsDemandAndIdleSeries(t *testing.T) {
	const pool = "p"

	claimedJobs.Reset()
	queuedJobs.Reset()
	idleReplicas.Reset()

	RecordDemand(pool, 1, 2)
	RecordIdleReplicas(pool, 3)
	Clear(pool)

	if got := testutil.CollectAndCount(claimedJobs); got != 0 {
		t.Fatalf("claimed jobs series after Clear = %d, want 0", got)
	}
	if got := testutil.CollectAndCount(queuedJobs); got != 0 {
		t.Fatalf("queued jobs series after Clear = %d, want 0", got)
	}
	if got := testutil.CollectAndCount(idleReplicas); got != 0 {
		t.Fatalf("idle replicas series after Clear = %d, want 0", got)
	}
}
