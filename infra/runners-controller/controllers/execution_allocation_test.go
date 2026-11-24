package controllers

import (
	"maps"
	"testing"

	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

func TestExecutionFloorOutranksRunnerWarmStockButNotQueuedJobs(t *testing.T) {
	const slot = int64(defaultExecutionSlotBytes)
	gib := int64(1 << 30)
	// Three workers at their chart floor of one slot (5 GiB carve-outs).
	var workers []executionWorker
	for _, node := range []string{"a", "b", "c"} {
		workers = append(workers, executionWorkersOf([]sandboxDaemon{{
			node: node, execution: true, memory: 5 * gib, floorBytes: 5 * gib, ceilingBytes: 17 * gib,
		}}, map[string]bool{node: true}, slot)...)
	}
	re, held := executionDemand(workers, 8, slot)
	if re.Load != 3 || re.Target != 8 || held != 3*slot {
		t.Fatalf("demand = %+v, held %d", re, held)
	}

	runner := scaling.PoolDemand{Name: "linux-4vcpu", PerPodCost: 8 * gib, MinWarmPoolFloor: 2, Floor: 2, Target: 2, HoursWithJobs: 300}
	// Room for the RE floor's five extra slots or the runners' two warm
	// Pods, not both: the floor wins.
	capacity := held + 5*slot + 8*gib
	got := scaling.AllocateCompute([]scaling.PoolDemand{runner, re}, capacity, nil)
	if want := map[string]int32{"linux-4vcpu": 1, executionPoolName: 8}; !maps.Equal(got, want) {
		t.Fatalf("warm contention: got %v, want %v", got, want)
	}

	// Two queued jobs are real load: the floor gives way, held slots stay.
	runner.Load, runner.Active, runner.InUse = 2, true, true
	got = scaling.AllocateCompute([]scaling.PoolDemand{runner, re}, held+16*gib, nil)
	if want := map[string]int32{"linux-4vcpu": 2, executionPoolName: 3}; !maps.Equal(got, want) {
		t.Fatalf("queued jobs: got %v, want %v", got, want)
	}
}

func TestExecutionWarmSlotsSpreadsOnlyTheFloor(t *testing.T) {
	gib := int64(1 << 30)
	daemons := []sandboxDaemon{
		{node: "a", execution: true, memory: 17 * gib, floorBytes: 5 * gib, ceilingBytes: 17 * gib},
		{node: "b", execution: true, memory: 5 * gib, floorBytes: 5 * gib, ceilingBytes: 17 * gib},
		{node: "c", execution: true, memory: 5 * gib, floorBytes: 5 * gib, ceilingBytes: 17 * gib},
		{node: "d", memory: 30 * gib}, // the agent daemon is not a worker
	}
	workers := executionWorkersOf(daemons, map[string]bool{"a": true, "b": true, "c": true, "d": true}, defaultExecutionSlotBytes)
	// Node a holds four slots for a build; a floor of five keeps it at two,
	// not four, so it shrinks back once its VMs are gone.
	got := executionWarmSlots(workers, 5)
	want := map[string]int32{"a.remote-execution": 2, "b.remote-execution": 2, "c.remote-execution": 1}
	if !maps.Equal(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	// A floor below the chart floors keeps every worker at its chart floor.
	if got := executionWarmSlots(workers, 1); !maps.Equal(got, map[string]int32{"a.remote-execution": 1, "b.remote-execution": 1, "c.remote-execution": 1}) {
		t.Fatalf("small floor: got %v", got)
	}
}
