package scaling

import "testing"

const (
	gib = int64(1024) * 1024 * 1024
	mib = int64(1024) * 1024
)

func TestAllocateFleet_UncontendedGrantsEveryTarget(t *testing.T) {
	// 100 GiB fleet, two small shapes — everything fits, each gets its
	// full target.
	pools := []PoolDemand{
		{Name: "small", PerPodCost: 2 * gib, Floor: 1, Load: 2, Target: 5},
		{Name: "med", PerPodCost: 4 * gib, Floor: 1, Load: 1, Target: 4},
	}
	got := AllocateFleet(pools, 100*gib, nil)

	if got["small"] != 5 {
		t.Errorf("small = %d, want 5", got["small"])
	}
	if got["med"] != 4 {
		t.Errorf("med = %d, want 4", got["med"])
	}
}

func TestAllocateFleet_RealLoadAlwaysGrantedEvenOverCapacity(t *testing.T) {
	// Floors + load exceed the fleet. Real need is honored in full;
	// the excess is the operator's "add a host" signal (goes Pending).
	pools := []PoolDemand{
		{Name: "a", PerPodCost: 16 * gib, Floor: 1, Load: 3, Target: 6},
		{Name: "b", PerPodCost: 16 * gib, Floor: 1, Load: 2, Target: 5},
	}
	// Only 32 GiB usable — 2 pods — but real load wants 5 pods.
	got := AllocateFleet(pools, 32*gib, nil)

	if got["a"] != 3 {
		t.Errorf("a = %d, want 3 (load honored in full)", got["a"])
	}
	if got["b"] != 2 {
		t.Errorf("b = %d, want 2 (load honored in full)", got["b"])
	}
}

func TestAllocateFleet_SqueezesSpeculativeHeadroomUnderContention(t *testing.T) {
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
	got := AllocateFleet(pools, 64*gib, nil)

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

func TestAllocateFleet_SqueezesIdleFloorForAnotherPoolsQueuedLoad(t *testing.T) {
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
	got := AllocateFleet(pools, 200*gib, nil)

	if got["big"] != 10 {
		t.Errorf("big = %d, want 10 (queued load wins over idle floor)", got["big"])
	}
	if got["small"] != 5 {
		t.Errorf("small = %d, want 5 (floor squeezed from 20 to fit big's load)", got["small"])
	}
}

func TestAllocateFleet_HeadroomSplitProportionally(t *testing.T) {
	// Two idle shapes, equal pod size, both want speculative headroom;
	// limited leftover splits proportionally to requested headroom.
	pools := []PoolDemand{
		{Name: "x", PerPodCost: 4 * gib, Floor: 1, Load: 0, Target: 5}, // wants 4 headroom
		{Name: "y", PerPodCost: 4 * gib, Floor: 1, Load: 0, Target: 3}, // wants 2 headroom
	}
	// Floors: 2 pods = 8 GiB. Fleet 8 GiB base + 12 GiB (3 pods) left.
	// Headroom demand: x=4, y=2 (6 total). 3 pods split 2:1 → x≈2, y≈1.
	got := AllocateFleet(pools, 20*gib, nil)

	if got["x"] != 3 { // floor 1 + 2 headroom
		t.Errorf("x = %d, want 3", got["x"])
	}
	if got["y"] != 2 { // floor 1 + 1 headroom
		t.Errorf("y = %d, want 2", got["y"])
	}
}

func TestAllocateFleet_NeverExceedsTarget(t *testing.T) {
	pools := []PoolDemand{
		{Name: "a", PerPodCost: 1 * gib, Floor: 1, Load: 0, Target: 2},
	}
	got := AllocateFleet(pools, 1000*gib, nil)
	if got["a"] != 2 {
		t.Errorf("a = %d, want 2 (capped at target)", got["a"])
	}
}

func TestAllocateFleet_ZeroCapacityHonorsLoadNotFloor(t *testing.T) {
	// Pure-function contract at fleetMem == 0: real load is still
	// granted (it would go Pending), while a speculative floor with no
	// load behind it is squeezed to zero rather than manufactured into
	// Pending Pods.
	//
	// NOTE: the AutoscalerReconciler never calls AllocateFleet with
	// fleetMem <= 0. It treats a zero or failed fleet-memory read as a
	// blip and falls back to the per-pool target (floor honored), so
	// this pins AllocateFleet's behavior for callers that pass 0, not
	// the deployed zero-node behavior.
	pools := []PoolDemand{
		{Name: "load", PerPodCost: 4 * gib, Floor: 2, Load: 3, Target: 5},
		{Name: "floor", PerPodCost: 4 * gib, Floor: 2, Load: 0, Target: 5},
	}
	got := AllocateFleet(pools, 0, nil)
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
// cases exercise the real Signals -> DesiredReplicas -> AllocateFleet
// composition the incident ran through.
func macDemand(name string, s Signals, k PolicyKnobs) PoolDemand {
	return PoolDemand{
		Name:       name,
		PerPodCost: 1,
		Floor:      k.MinWarmPoolFloor,
		Load:       s.Load(),
		Target:     DesiredReplicas(s, k),
	}
}

func TestAllocateFleet_WithheldDemand(t *testing.T) {
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
			got := AllocateFleet(tc.pools, tc.capacity, nil)
			for name, want := range tc.want {
				if got[name] != want {
					t.Errorf("%s = %d, want %d (full allocation: %v)", name, got[name], want, got)
				}
			}
		})
	}
}

func TestAllocateFleet_EmptyFleet(t *testing.T) {
	got := AllocateFleet(nil, 100*gib, nil)
	if len(got) != 0 {
		t.Errorf("got %v, want empty", got)
	}
}

// The shape cap exists because `maxReplicas` is per pool: five Xcode
// pools each allowed two 12 vCPU runners compose to ten, and the byte
// budget cannot catch it because it pools memory from M2-L hosts that
// cannot seat the shape at all.
func TestAllocateFleetCapsPoolsSharingAShape(t *testing.T) {
	const big = 28672 * mib

	pools := []PoolDemand{
		{Name: "macos-26-6-12vcpu", PerPodCost: big, Load: 1, Target: 2, ShapeKey: "12000m-28672Mi"},
		{Name: "macos-26-5-12vcpu", PerPodCost: big, Load: 1, Target: 2, ShapeKey: "12000m-28672Mi"},
		{Name: "macos-26-3-12vcpu", PerPodCost: big, Load: 1, Target: 2, ShapeKey: "12000m-28672Mi"},
	}

	// The fleet advertises 157696 MiB, which the byte budget alone reads
	// as five 28 GiB slots. Only two hosts can actually seat one.
	got := AllocateFleet(pools, 157696*mib, map[string]int32{"12000m-28672Mi": 2})

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
func TestAllocateFleetShapeCapPrefersLoadOverWarmth(t *testing.T) {
	const big = 28672 * mib

	pools := []PoolDemand{
		{Name: "a-idle", PerPodCost: big, Floor: 1, Target: 1, ShapeKey: "s"},
		{Name: "b-queued", PerPodCost: big, Load: 1, Target: 1, ShapeKey: "s"},
	}

	got := AllocateFleet(pools, 1000*gib, map[string]int32{"s": 1})

	if got["b-queued"] != 1 || got["a-idle"] != 0 {
		t.Fatalf("the one seat should go to real queued work, got %v", got)
	}
}

// Two pools contending for a single seat must not both lose it, and the
// winner must be the same on every reconcile.
func TestAllocateFleetShapeCapSplitsDeterministically(t *testing.T) {
	const big = 28672 * mib

	pools := []PoolDemand{
		{Name: "b", PerPodCost: big, Load: 2, Target: 2, ShapeKey: "s"},
		{Name: "a", PerPodCost: big, Load: 2, Target: 2, ShapeKey: "s"},
	}

	first := AllocateFleet(pools, 1000*gib, map[string]int32{"s": 2})
	second := AllocateFleet(pools, 1000*gib, map[string]int32{"s": 2})

	if first["a"] != 1 || first["b"] != 1 {
		t.Fatalf("a single round should hand each contender one seat, got %v", first)
	}
	if first["a"] != second["a"] || first["b"] != second["b"] {
		t.Fatalf("allocation is not deterministic: %v then %v", first, second)
	}
}

// Pools of other shapes, and pools with no ShapeKey, are untouched.
func TestAllocateFleetShapeCapLeavesOtherShapesAlone(t *testing.T) {
	pools := []PoolDemand{
		{Name: "big", PerPodCost: 28672 * mib, Load: 3, Target: 3, ShapeKey: "big"},
		{Name: "small", PerPodCost: 14336 * mib, Load: 4, Target: 4, ShapeKey: "small"},
		{Name: "unkeyed", PerPodCost: 14336 * mib, Load: 2, Target: 2},
	}

	got := AllocateFleet(pools, 1000*gib, map[string]int32{"big": 2})

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
