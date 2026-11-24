package scaling

import (
	"maps"
	"testing"
	"time"
)

const (
	gib = int64(1024) * 1024 * 1024
	mib = int64(1024) * 1024
)

func TestAllocateCompute_UncontendedGrantsEveryTarget(t *testing.T) {
	// 100 GiB fleet, two small shapes — everything fits, each gets its
	// full target.
	pools := []PoolDemand{
		{Name: "small", PerPodCost: 2 * gib, Floor: 1, Load: 2, Target: 5},
		{Name: "med", PerPodCost: 4 * gib, Floor: 1, Load: 1, Target: 4},
	}
	got := AllocateCompute(pools, 100*gib, nil)

	if got["small"] != 5 {
		t.Errorf("small = %d, want 5", got["small"])
	}
	if got["med"] != 4 {
		t.Errorf("med = %d, want 4", got["med"])
	}
}

func TestAllocateCompute_RealLoadAlwaysGrantedEvenOverCapacity(t *testing.T) {
	// Floors + load exceed the fleet. Real need is honored in full;
	// the excess is the operator's "add a host" signal (goes Pending).
	pools := []PoolDemand{
		{Name: "a", PerPodCost: 16 * gib, Floor: 1, Load: 3, Target: 6},
		{Name: "b", PerPodCost: 16 * gib, Floor: 1, Load: 2, Target: 5},
	}
	// Only 32 GiB usable — 2 pods — but real load wants 5 pods.
	got := AllocateCompute(pools, 32*gib, nil)

	if got["a"] != 3 {
		t.Errorf("a = %d, want 3 (load honored in full)", got["a"])
	}
	if got["b"] != 2 {
		t.Errorf("b = %d, want 2 (load honored in full)", got["b"])
	}
}

func TestAllocateCompute_SqueezesSpeculativeHeadroomUnderContention(t *testing.T) {
	// The reclaim case: shape "busy" has real queued work; shape "idle"
	// only has a p95-driven speculative buffer (load 0, target 5). Fleet
	// fits busy's real load + floors, but not idle's speculative warm.
	// idle should fall back toward its floor so busy's real work fits.
	pools := []PoolDemand{
		{Name: "busy", PerPodCost: 8 * gib, Floor: 1, Load: 6, Target: 8},
		{Name: "idle", PerPodCost: 8 * gib, Floor: 1, Load: 0, Target: 5},
	}
	// 64 GiB usable = 8 pods. busy load 6 (48 GiB). Floors: busy 0 (load
	// already > floor), idle 1 (8 GiB) → fit, 8 GiB left for headroom.
	// Headroom wants: busy 2, idle 4 (6 total). 1 pod split
	// proportionally → busy ~0, idle ~0 (rounding down). The point:
	// idle does NOT get its speculative 5; busy's real load is intact.
	got := AllocateCompute(pools, 64*gib, nil)

	if got["busy"] < 6 {
		t.Errorf("busy = %d, want >= 6 (real load protected)", got["busy"])
	}
	if got["idle"] > 2 {
		t.Errorf("idle = %d, want squeezed toward floor (<= 2)", got["idle"])
	}
	if got["idle"] < 1 {
		t.Errorf("idle = %d, want >= floor 1", got["idle"])
	}
}

func TestAllocateCompute_SqueezesIdleFloorForAnotherPoolsQueuedLoad(t *testing.T) {
	// The production case this re-tiering fixes: a small shape sits at a
	// large warm floor (mostly idle Pods), while a big shape has real
	// queued load that doesn't fit. Real load outranks the idle floor —
	// the small shape's floor is squeezed below its configured value so
	// the big shape's queued work schedules, instead of leaving it Pending
	// while idle Pods hold reservations.
	pools := []PoolDemand{
		// small: floor 20 (all idle, no real load behind it).
		{Name: "small", PerPodCost: 8 * gib, Floor: 20, Load: 0, Target: 25},
		// big: real queued load 10, no floor — pure demand.
		{Name: "big", PerPodCost: 16 * gib, Floor: 0, Load: 10, Target: 10},
	}
	// 200 GiB usable. big's load = 160 GiB granted first, leaving 40 GiB
	// (5 pods of 8 GiB) for small's floor of 20 → squeezed to 5.
	got := AllocateCompute(pools, 200*gib, nil)

	if got["big"] != 10 {
		t.Errorf("big = %d, want 10 (queued load wins over idle floor)", got["big"])
	}
	if got["small"] != 5 {
		t.Errorf("small = %d, want 5 (floor squeezed from 20 to fit big's load)", got["small"])
	}
}

func TestAllocateCompute_HeadroomSplitProportionally(t *testing.T) {
	// Two idle shapes, equal pod size, both want speculative headroom;
	// limited leftover splits proportionally to requested headroom.
	pools := []PoolDemand{
		{Name: "x", PerPodCost: 4 * gib, Floor: 1, Load: 0, Target: 5}, // wants 4 headroom
		{Name: "y", PerPodCost: 4 * gib, Floor: 1, Load: 0, Target: 3}, // wants 2 headroom
	}
	// Floors: 2 pods = 8 GiB. Fleet 8 GiB base + 12 GiB (3 pods) left.
	// Headroom demand: x=4, y=2 (6 total). 3 pods split 2:1 → x≈2, y≈1.
	got := AllocateCompute(pools, 20*gib, nil)

	if got["x"] != 3 { // floor 1 + 2 headroom
		t.Errorf("x = %d, want 3", got["x"])
	}
	if got["y"] != 2 { // floor 1 + 1 headroom
		t.Errorf("y = %d, want 2", got["y"])
	}
}

func TestAllocateCompute_NeverExceedsTarget(t *testing.T) {
	pools := []PoolDemand{
		{Name: "a", PerPodCost: 1 * gib, Floor: 1, Load: 0, Target: 2},
	}
	got := AllocateCompute(pools, 1000*gib, nil)
	if got["a"] != 2 {
		t.Errorf("a = %d, want 2 (capped at target)", got["a"])
	}
}

func TestAllocateCompute_ZeroCapacityHonorsLoadNotFloor(t *testing.T) {
	// Pure-function contract at fleetMem == 0: real load is still
	// granted (it would go Pending), while a speculative floor with no
	// load behind it is squeezed to zero rather than manufactured into
	// Pending Pods.
	//
	// NOTE: the AutoscalerReconciler never calls AllocateCompute with
	// fleetMem <= 0. It treats a zero or failed fleet-memory read as a
	// blip and falls back to the per-pool target (floor honored), so
	// this pins AllocateCompute's behavior for callers that pass 0, not
	// the deployed zero-node behavior.
	pools := []PoolDemand{
		{Name: "load", PerPodCost: 4 * gib, Floor: 2, Load: 3, Target: 5},
		{Name: "floor", PerPodCost: 4 * gib, Floor: 2, Load: 0, Target: 5},
	}
	got := AllocateCompute(pools, 0, nil)
	if got["load"] != 3 {
		t.Errorf("load = %d, want 3 (real load honored even at zero capacity)", got["load"])
	}
	if got["floor"] != 0 {
		t.Errorf("floor = %d, want 0 (speculative floor squeezed, not left Pending)", got["floor"])
	}
}

// macDemand builds a macOS PoolDemand (1 Mac mini = 1 slot = 1 VM, so
// PerPodCost is 1) the way the reconciler does: Load and Target both
// derived from the server's signals rather than hand-picked, so these
// cases exercise the real Signals -> DesiredReplicas -> AllocateCompute
// composition the incident ran through.
func macDemand(name string, s Signals, k PolicyKnobs) PoolDemand {
	return PoolDemand{
		Name:             name,
		PerPodCost:       1,
		Floor:            WarmFloor(s, k),
		MinWarmPoolFloor: k.MinWarmPoolFloor,
		Active:           s.CurrentOccupancy()+s.Queued > 0,
		InUse:            s.InUse(),
		ColdJobs:         s.ColdJobs,
		HoursWithJobs:    s.HoursWithJobs,
		Load:             s.Load(),
		Target:           DesiredReplicas(s, k),
	}
}

func TestAllocateCompute_WithheldDemand(t *testing.T) {
	// Knobs as deployed: the saturated shape carries a warm floor, the
	// blocked shapes carry none — so nothing but the withheld signal
	// itself can win them a Pod.
	saturated := PolicyKnobs{MinWarmPoolFloor: 1, MaxReplicas: 30}
	blocked := PolicyKnobs{MinWarmPoolFloor: 0, MaxReplicas: 30}

	tests := []struct {
		name     string
		pools    []PoolDemand
		capacity int64
		want     map[string]int32
	}{
		{
			// The 2026-08-12 incident, to its numbers: 9 host slots, all
			// held by macos-26-6, while macos-26-0-1 and macos-26-3 each
			// hold one queued job withheld because the account is at its
			// memory limit. Both must come out with a Pod: tier 1 is
			// granted past capacity, so the surplus goes Pending and the
			// reconciler reaps an idle sibling Pod after cooldown.
			name: "blocked pools each get a Pod on a saturated fleet",
			pools: []PoolDemand{
				macDemand("macos-26-6", Signals{Occupied: 9, P95ConcurrentLastHour: 9}, saturated),
				macDemand("macos-26-0-1", Signals{Withheld: 1}, blocked),
				macDemand("macos-26-3", Signals{Withheld: 1}, blocked),
			},
			capacity: 9,
			want: map[string]int32{
				"macos-26-6":   9, // real load still honored in full
				"macos-26-0-1": 1,
				"macos-26-3":   1,
			},
		},
		{
			// The same fleet as the server reported it before this change
			// (and as an older server still reports it mid-rollout):
			// withheld work is invisible, both pools read as idle, and a
			// saturated fleet leaves them at zero forever. This is the
			// starvation being fixed, pinned so it can't quietly return.
			name: "without the withheld signal blocked pools stay starved",
			pools: []PoolDemand{
				macDemand("macos-26-6", Signals{Occupied: 9, P95ConcurrentLastHour: 9}, saturated),
				macDemand("macos-26-0-1", Signals{}, blocked),
				macDemand("macos-26-3", Signals{}, blocked),
			},
			capacity: 9,
			want: map[string]int32{
				"macos-26-6":   9,
				"macos-26-0-1": 0,
				"macos-26-3":   0,
			},
		},
		{
			// The min(1, ...) cap. A deep withheld backlog must not size
			// the pool for work dispatch will refuse — that is exactly the
			// idle-Pod squatting the server-side withholding exists to
			// prevent. One Pod is enough to race for freed headroom.
			name: "many withheld jobs still buy exactly one Pod",
			pools: []PoolDemand{
				macDemand("macos-26-6", Signals{Occupied: 9, P95ConcurrentLastHour: 9}, saturated),
				macDemand("macos-26-0-1", Signals{Withheld: 12}, blocked),
				macDemand("macos-26-3", Signals{Withheld: 40}, blocked),
			},
			capacity: 9,
			want: map[string]int32{
				"macos-26-6":   9,
				"macos-26-0-1": 1,
				"macos-26-3":   1,
			},
		},
		{
			// The cap holds when capacity is not the constraint either:
			// spare slots go to the saturated shape's p95 headroom, not
			// to speculative Pods for blocked work.
			name: "spare capacity does not widen blocked demand past one",
			pools: []PoolDemand{
				macDemand("macos-26-6", Signals{Occupied: 9, P95ConcurrentLastHour: 9}, saturated),
				macDemand("macos-26-0-1", Signals{Withheld: 12}, blocked),
			},
			capacity: 20,
			want: map[string]int32{
				"macos-26-6":   10, // load 9 + its p95 warm slack
				"macos-26-0-1": 1,
			},
		},
		{
			// Blocked demand is tier 1, so it must not be funded by
			// squeezing another pool's *real* load — only its idle warm
			// capacity yields.
			name: "blocked demand does not displace a sibling's real load",
			pools: []PoolDemand{
				macDemand("macos-26-6", Signals{Occupied: 9, P95ConcurrentLastHour: 9}, saturated),
				macDemand("macos-26-0-1", Signals{Queued: 3, Withheld: 5}, blocked),
			},
			capacity: 9,
			want: map[string]int32{
				"macos-26-6":   9, // untouched
				"macos-26-0-1": 4, // 3 dispatchable + 1 for the blocked tail
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := AllocateCompute(tc.pools, tc.capacity, nil)
			for name, want := range tc.want {
				if got[name] != want {
					t.Errorf("%s = %d, want %d (full allocation: %v)", name, got[name], want, got)
				}
			}
		})
	}
}

func TestAllocateCompute_EmptyFleet(t *testing.T) {
	got := AllocateCompute(nil, 100*gib, nil)
	if len(got) != 0 {
		t.Errorf("got %v, want empty", got)
	}
}

// The shape cap exists because `maxReplicas` is per pool: five Xcode
// pools each allowed two 12 vCPU runners compose to ten, and the byte
// budget cannot catch it because it pools memory from M2-L hosts that
// cannot seat the shape at all.
func TestAllocateComputeCapsPoolsSharingAShape(t *testing.T) {
	const big = 28672 * mib

	pools := []PoolDemand{
		{Name: "macos-26-6-12vcpu", PerPodCost: big, Load: 1, Target: 2, ShapeKey: "12000m-28672Mi"},
		{Name: "macos-26-5-12vcpu", PerPodCost: big, Load: 1, Target: 2, ShapeKey: "12000m-28672Mi"},
		{Name: "macos-26-3-12vcpu", PerPodCost: big, Load: 1, Target: 2, ShapeKey: "12000m-28672Mi"},
	}

	// The fleet advertises 157696 MiB, which the byte budget alone reads
	// as five 28 GiB slots. Only two hosts can actually seat one.
	got := AllocateCompute(pools, 157696*mib, map[string]int32{"12000m-28672Mi": 2})

	var total int32
	for _, v := range got {
		total += v
	}
	if total != 2 {
		t.Fatalf("granted %d runners for a shape only two hosts can seat: %v", total, got)
	}
}

// Load is granted before floor and headroom inside the cap, so a pool
// with a queued job beats a sibling that only wants to stay warm.
func TestAllocateComputeShapeCapPrefersLoadOverWarmth(t *testing.T) {
	const big = 28672 * mib

	pools := []PoolDemand{
		{Name: "a-idle", PerPodCost: big, Floor: 1, Target: 1, ShapeKey: "s"},
		{Name: "b-queued", PerPodCost: big, Load: 1, Target: 1, ShapeKey: "s"},
	}

	got := AllocateCompute(pools, 1000*gib, map[string]int32{"s": 1})

	if got["b-queued"] != 1 || got["a-idle"] != 0 {
		t.Fatalf("the one seat should go to real queued work, got %v", got)
	}
}

// Two pools contending for a single seat must not both lose it, and the
// winner must be the same on every reconcile.
func TestAllocateComputeShapeCapSplitsDeterministically(t *testing.T) {
	const big = 28672 * mib

	pools := []PoolDemand{
		{Name: "b", PerPodCost: big, Load: 2, Target: 2, ShapeKey: "s"},
		{Name: "a", PerPodCost: big, Load: 2, Target: 2, ShapeKey: "s"},
	}

	first := AllocateCompute(pools, 1000*gib, map[string]int32{"s": 2})
	second := AllocateCompute(pools, 1000*gib, map[string]int32{"s": 2})

	if first["a"] != 1 || first["b"] != 1 {
		t.Fatalf("a single round should hand each contender one seat, got %v", first)
	}
	if first["a"] != second["a"] || first["b"] != second["b"] {
		t.Fatalf("allocation is not deterministic: %v then %v", first, second)
	}
}

// Pools of other shapes, and pools with no ShapeKey, are untouched.
func TestAllocateComputeShapeCapLeavesOtherShapesAlone(t *testing.T) {
	pools := []PoolDemand{
		{Name: "big", PerPodCost: 28672 * mib, Load: 3, Target: 3, ShapeKey: "big"},
		{Name: "small", PerPodCost: 14336 * mib, Load: 4, Target: 4, ShapeKey: "small"},
		{Name: "unkeyed", PerPodCost: 14336 * mib, Load: 2, Target: 2},
	}

	got := AllocateCompute(pools, 1000*gib, map[string]int32{"big": 2})

	if got["big"] != 2 {
		t.Fatalf("capped shape: want 2, got %d", got["big"])
	}
	if got["small"] != 4 {
		t.Fatalf("uncapped shape must be untouched, got %d", got["small"])
	}
	if got["unkeyed"] != 2 {
		t.Fatalf("a pool with no ShapeKey must be untouched, got %d", got["unkeyed"])
	}
}

func TestAllocateCompute_OneShortFloorTierKeepsTheFloorsThatFit(t *testing.T) {
	// A 14-slot rack with one warm floor per Xcode image. 27.0 is running
	// seven jobs, so the eight other images' floors want eight slots where
	// seven are left. Only one floor yields, and it is an idle image's,
	// not the one used in the last hour.
	slot := 24 * gib
	pools := []PoolDemand{
		{Name: "27-0", PerPodCost: slot, Floor: 1, Load: 7, Target: 8},
		{Name: "26-3", PerPodCost: slot, Floor: 1, Load: 0, Target: 2},
	}
	for _, name := range []string{"26-0-1", "26-1-1", "26-4-1", "26-5", "26-6", "27-1", "27-2-beta"} {
		pools = append(pools, PoolDemand{Name: name, PerPodCost: slot, Floor: 1, Load: 0, Target: 1})
	}

	got := AllocateCompute(pools, 14*slot, nil)

	if got["27-0"] != 7 {
		t.Errorf("27-0 = %d, want 7 (its load)", got["27-0"])
	}
	if got["26-3"] != 1 {
		t.Errorf("26-3 = %d, want 1 (used in the last hour, keeps its floor)", got["26-3"])
	}
	if got["27-2-beta"] != 0 {
		t.Errorf("27-2-beta = %d, want 0 (last by name among idle images, yields)", got["27-2-beta"])
	}
	var total int32
	for _, n := range got {
		total += n
	}
	if total != 14 {
		t.Errorf("granted %d slots, want all 14 (%v)", total, got)
	}
}

func TestAllocateCompute_FloorsOfPoolsInUseBeforeIdlePools(t *testing.T) {
	// A full rack: 27-1 runs five jobs and keeps its learned spare of three
	// above them; 26-3 and 27-2 had no job in the last hour and only hold
	// their learned floors. Two slots are left once 27-1's spare is in, and
	// the idle pools share those instead of all three splitting the shortfall.
	slot := 14 * gib
	pools := []PoolDemand{
		{Name: "27-1", PerPodCost: slot, Floor: 8, Load: 5, Target: 8, InUse: true},
		{Name: "26-3", PerPodCost: slot, Floor: 3, Target: 3},
		{Name: "27-2", PerPodCost: slot, Floor: 2, Target: 2},
	}

	got := AllocateCompute(pools, 10*slot, nil)

	if got["27-1"] != 8 {
		t.Errorf("27-1 = %d, want 8 (its load and its whole spare)", got["27-1"])
	}
	if idle := got["26-3"] + got["27-2"]; idle != 2 {
		t.Errorf("idle pools = %d, want the 2 slots left (%v)", idle, got)
	}
}

func TestAllocateCompute_IdlePoolsKeepTheirFloorsWhenTheFleetHasRoom(t *testing.T) {
	slot := 14 * gib
	pools := []PoolDemand{
		{Name: "27-1", PerPodCost: slot, Floor: 8, Load: 5, Target: 8, InUse: true},
		{Name: "26-3", PerPodCost: slot, Floor: 3, Target: 3},
	}

	got := AllocateCompute(pools, 26*slot, nil)

	if got["27-1"] != 8 || got["26-3"] != 3 {
		t.Errorf("uncontended fleet should fund every floor, got %v", got)
	}
}

func TestAllocateCompute_IdlePoolsFloorStillOutranksHeadroom(t *testing.T) {
	slot := 14 * gib
	pools := []PoolDemand{
		{Name: "peak", PerPodCost: slot, Load: 1, Target: 4, InUse: true},
		{Name: "idle", PerPodCost: slot, Floor: 2, Target: 2},
	}

	// One load, one recent-use baseline and the idle floor fit. Only
	// peak's remaining speculative headroom must yield.
	got := AllocateCompute(pools, 4*slot, nil)

	if got["peak"] != 2 || got["idle"] != 2 {
		t.Errorf("an idle pool's floor should be funded before p95 headroom, got %v", got)
	}
}

func TestAllocateCompute_BurstPriority(t *testing.T) {
	knobs := PolicyKnobs{MaxLearnedWarmPoolFloor: 4, MaxReplicas: 20}
	for _, tc := range []struct {
		name     string
		pools    []PoolDemand
		capacity int32
		want     map[string]int32
	}{
		{
			name: "recent quiet pool keeps baseline but yields burst to active pool",
			pools: []PoolDemand{
				macDemand("active", Signals{Occupied: 1, LearnedWarmFloor: 3}, knobs),
				macDemand("quiet", Signals{P95ConcurrentLastHour: 3, LearnedWarmFloor: 3, HoursWithJobs: 300}, knobs),
			},
			capacity: 5, want: map[string]int32{"active": 4, "quiet": 1},
		},
		{
			name: "whole active bursts ordered by usage rather than name",
			pools: []PoolDemand{
				macDemand("a", Signals{Queued: 1, LearnedWarmFloor: 4, HoursWithJobs: 20}, knobs),
				macDemand("z", Signals{Queued: 1, LearnedWarmFloor: 4, HoursWithJobs: 100}, knobs),
			},
			capacity: 7, want: map[string]int32{"a": 2, "z": 5},
		},
		{
			name: "recency then name break active usage ties",
			pools: []PoolDemand{
				{Name: "a", PerPodCost: 1, Load: 1, Floor: 4, Target: 4, Active: true, InUse: true, LastDemandAt: time.Unix(1, 0)},
				{Name: "z", PerPodCost: 1, Load: 1, Floor: 4, Target: 4, Active: true, InUse: true, LastDemandAt: time.Unix(2, 0)},
				{Name: "b", PerPodCost: 1, Load: 1, Floor: 4, Target: 4, Active: true, InUse: true, LastDemandAt: time.Unix(2, 0)},
			},
			capacity: 8, want: map[string]int32{"a": 2, "z": 2, "b": 4},
		},
		{
			name: "one baseline fits and usage wins before name",
			pools: []PoolDemand{
				macDemand("a", Signals{P95ConcurrentLastHour: 2, LearnedWarmFloor: 4, HoursWithJobs: 20}, knobs),
				macDemand("z", Signals{P95ConcurrentLastHour: 2, LearnedWarmFloor: 4, HoursWithJobs: 100}, knobs),
			},
			capacity: 1, want: map[string]int32{"a": 0, "z": 1},
		},
		{
			name: "explicit minimum survives before active burst",
			pools: []PoolDemand{
				macDemand("active", Signals{Queued: 1, LearnedWarmFloor: 4}, knobs),
				macDemand("unused", Signals{}, PolicyKnobs{MinWarmPoolFloor: 1, MaxReplicas: 20}),
			},
			capacity: 5, want: map[string]int32{"active": 4, "unused": 1},
		},
		{
			name: "pool with a learned floor keeps its first warm runner before an active burst",
			pools: []PoolDemand{
				macDemand("active", Signals{Queued: 1, LearnedWarmFloor: 4}, knobs),
				macDemand("learned", Signals{LearnedWarmFloor: 1}, knobs),
			},
			capacity: 5, want: map[string]int32{"active": 4, "learned": 1},
		},
		{
			// The withheld pool keeps its Pod for the blocked work and, like
			// every pool with a learned floor, one warm runner; the rest of
			// its burst still waits behind the active pool's.
			name: "withheld-only contender earns no active burst priority",
			pools: []PoolDemand{
				macDemand("active", Signals{Queued: 1, LearnedWarmFloor: 3}, knobs),
				macDemand("withheld", Signals{Withheld: 100, LearnedWarmFloor: 4, HoursWithJobs: 300}, knobs),
			},
			capacity: 5, want: map[string]int32{"active": 3, "withheld": 2},
		},
		{
			name: "recent burst precedes more frequently used idle pool",
			pools: []PoolDemand{
				macDemand("recent", Signals{P95ConcurrentLastHour: 2, LearnedWarmFloor: 4}, knobs),
				macDemand("idle", Signals{LearnedWarmFloor: 4, HoursWithJobs: 300}, knobs),
			},
			capacity: 5, want: map[string]int32{"recent": 4, "idle": 1},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for _, shapeLimited := range []bool{false, true} {
				capacity := int64(tc.capacity)
				var caps map[string]int32
				if shapeLimited {
					capacity = 100
					caps = map[string]int32{"shared": tc.capacity}
				}
				for _, reverse := range []bool{false, true} {
					pools := append([]PoolDemand(nil), tc.pools...)
					for i := range pools {
						pools[i].ShapeKey = "shared"
					}
					if reverse {
						for i, j := 0, len(pools)-1; i < j; i, j = i+1, j-1 {
							pools[i], pools[j] = pools[j], pools[i]
						}
					}
					if got := AllocateCompute(pools, capacity, caps); !maps.Equal(got, tc.want) {
						t.Errorf("shapeLimited=%v reverse=%v: got %v, want %v", shapeLimited, reverse, got, tc.want)
					}
				}
			}
		})
	}
}

// Inside a capped shape, the floor of a pool in use is seated before that of
// an idle one, whatever their names.
func TestAllocateComputeShapeCapPrefersFloorsOfPoolsInUse(t *testing.T) {
	const big = 28672 * mib

	pools := []PoolDemand{
		{Name: "a-idle", PerPodCost: big, Floor: 1, Target: 1, ShapeKey: "s"},
		{Name: "b-in-use", PerPodCost: big, Floor: 1, Target: 1, ShapeKey: "s", InUse: true},
	}

	got := AllocateCompute(pools, 1000*gib, map[string]int32{"s": 1})

	if got["b-in-use"] != 1 || got["a-idle"] != 0 {
		t.Fatalf("the one seat should keep the pool in use warm, got %v", got)
	}
}

// A full rack after a quiet hour: no pool is in use, 27-1 had a fan-out this
// morning and 26-3 only runs a nightly job. Both hold a learned floor of
// eight and six seats are left. Each keeps its first warm runner, and 27-1
// gets the rest, rather than the two splitting them and neither having its
// burst warm.
func TestAllocateCompute_IdleFloorsGoToTheMostRecentlyUsedPool(t *testing.T) {
	slot := 24 * gib
	now := time.Date(2026, 11, 13, 11, 16, 0, 0, time.UTC)
	pools := []PoolDemand{
		{Name: "26-3", PerPodCost: slot, Floor: 8, Target: 8, LastDemandAt: now.Add(-11 * time.Hour)},
		{Name: "27-1", PerPodCost: slot, Floor: 8, Target: 8, LastDemandAt: now.Add(-20 * time.Minute)},
		{Name: "27-0", PerPodCost: slot, Floor: 9, Load: 2, Target: 9, InUse: true, LastDemandAt: now},
	}

	got := AllocateCompute(pools, 15*slot, nil)

	if got["27-0"] != 9 {
		t.Errorf("27-0 = %d, want 9 (in use: its load and its floor)", got["27-0"])
	}
	if got["27-1"] != 5 || got["26-3"] != 1 {
		t.Errorf("26-3 should keep one warm runner and 27-1 the other five, got 27-1=%d 26-3=%d", got["27-1"], got["26-3"])
	}
}

// Every pool with a learned floor keeps its first warm runner, then the most
// recently used pool's burst takes what is left before the next one's.
func TestAllocateCompute_IdleFloorsByRecencySpendWhatIsLeft(t *testing.T) {
	slot := 24 * gib
	now := time.Date(2026, 11, 13, 11, 16, 0, 0, time.UTC)
	pools := []PoolDemand{
		{Name: "a-never", PerPodCost: slot, Floor: 2, Target: 2},
		{Name: "b-old", PerPodCost: slot, Floor: 3, Target: 3, LastDemandAt: now.Add(-20 * time.Hour)},
		{Name: "c-recent", PerPodCost: slot, Floor: 3, Target: 3, LastDemandAt: now.Add(-2 * time.Hour)},
	}

	got := AllocateCompute(pools, 5*slot, nil)

	if got["c-recent"] != 3 || got["b-old"] != 1 || got["a-never"] != 1 {
		t.Errorf("want c-recent=3 b-old=1 a-never=1, got %v", got)
	}
}

// The rack at 15:30 on 2026-11-13: 26-3's nightly-only jobs finished four
// minutes after 27-1's, and 27-0 holds the rest. Recency alone gave 26-3 all
// seven seats left; 27-1, with jobs in 249 hours of the last two weeks
// against 26-3's 34, gets all but 26-3's first warm runner.
func TestAllocateCompute_IdleFloorsGoToThePoolUsedInMoreHours(t *testing.T) {
	slot := 24 * gib
	now := time.Date(2026, 11, 13, 15, 30, 0, 0, time.UTC)
	pools := []PoolDemand{
		{Name: "26-3", PerPodCost: slot, Floor: 8, Target: 8, HoursWithJobs: 34, LastDemandAt: now.Add(-60 * time.Minute)},
		{Name: "27-1", PerPodCost: slot, Floor: 11, Target: 11, HoursWithJobs: 249, LastDemandAt: now.Add(-64 * time.Minute)},
		{Name: "27-0", PerPodCost: slot, Floor: 11, Load: 4, Target: 11, InUse: true, HoursWithJobs: 257, LastDemandAt: now},
	}

	got := AllocateCompute(pools, 18*slot, nil)

	if got["27-0"] != 11 {
		t.Errorf("27-0 = %d, want 11 (in use: its load and its floor)", got["27-0"])
	}
	if got["27-1"] != 6 || got["26-3"] != 1 {
		t.Errorf("26-3 should keep one warm runner and 27-1 the other six, got 27-1=%d 26-3=%d", got["27-1"], got["26-3"])
	}
}

// The rack on 2026-11-19 at 10:34: 26-6 (jobs in 270 hours, 360 of them past
// the first of their burst) held five idle runners while 27-1 (231 hours,
// 2159 such jobs, all customers') had one, and a customer's next fan-out of
// seven booted cold. The floor goes to the pool whose bursts it serves.
func TestAllocateCompute_FloorsGoToThePoolWithMoreColdJobs(t *testing.T) {
	slot := 24 * gib
	now := time.Date(2026, 11, 19, 10, 34, 0, 0, time.UTC)
	pools := []PoolDemand{
		{Name: "26-6", PerPodCost: slot, Floor: 6, Load: 1, Target: 6, InUse: true, Active: true, ColdJobs: 360, HoursWithJobs: 270, LastDemandAt: now},
		{Name: "27-1", PerPodCost: slot, Floor: 17, Load: 6, Target: 17, InUse: true, Active: true, ColdJobs: 2159, HoursWithJobs: 231, LastDemandAt: now},
	}

	// Ten seats past both pools' load and baseline (2 and 7): 27-1's ten
	// learned spares take them all. By hours with jobs, 26-6 took four first.
	got := AllocateCompute(pools, 19*slot, nil)
	if got["27-1"] != 17 || got["26-6"] != 2 {
		t.Errorf("byte budget: want 27-1=17 26-6=2, got %v", got)
	}

	for i := range pools {
		pools[i].ShapeKey = "8vcpu"
	}
	got = AllocateCompute(pools, 1000*gib, map[string]int32{"8vcpu": 19})
	if got["27-1"] != 17 || got["26-6"] != 2 {
		t.Errorf("shape cap: want 27-1=17 26-6=2, got %v", got)
	}
}

// The shape cap ranks idle floors by hours with jobs before recency too.
func TestAllocateComputeShapeCapSeatsIdleFloorsByHoursWithJobs(t *testing.T) {
	slot := 24 * gib
	now := time.Date(2026, 11, 13, 15, 30, 0, 0, time.UTC)
	pools := []PoolDemand{
		{Name: "26-3", PerPodCost: slot, Floor: 8, Target: 8, ShapeKey: "8vcpu", HoursWithJobs: 34, LastDemandAt: now.Add(-60 * time.Minute)},
		{Name: "27-1", PerPodCost: slot, Floor: 11, Target: 11, ShapeKey: "8vcpu", HoursWithJobs: 249, LastDemandAt: now.Add(-64 * time.Minute)},
	}

	got := AllocateCompute(pools, 1000*gib, map[string]int32{"8vcpu": 13})

	if got["27-1"] != 11 || got["26-3"] != 2 {
		t.Errorf("want 27-1=11 26-3=2, got %v", got)
	}
}

// The shape cap seats idle floors the same way: the rack's 8 vCPU seats are
// capped per shape before the byte budget, and that cap decides first.
func TestAllocateComputeShapeCapSeatsIdleFloorsByRecency(t *testing.T) {
	slot := 24 * gib
	now := time.Date(2026, 11, 13, 11, 16, 0, 0, time.UTC)
	pools := []PoolDemand{
		{Name: "26-3", PerPodCost: slot, Floor: 8, Target: 8, ShapeKey: "8vcpu", LastDemandAt: now.Add(-11 * time.Hour)},
		{Name: "27-1", PerPodCost: slot, Floor: 8, Target: 8, ShapeKey: "8vcpu", LastDemandAt: now.Add(-20 * time.Minute)},
	}

	got := AllocateCompute(pools, 1000*gib, map[string]int32{"8vcpu": 10})

	if got["27-1"] != 8 || got["26-3"] != 2 {
		t.Errorf("want 27-1=8 26-3=2, got %v", got)
	}
}
