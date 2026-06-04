package scaling

import "testing"

const gib = int64(1024) * 1024 * 1024

func TestAllocateFleet_UncontendedGrantsEveryTarget(t *testing.T) {
	// 100 GiB fleet, two small shapes — everything fits, each gets its
	// full target.
	pools := []PoolDemand{
		{Name: "small", PodMemBytes: 2 * gib, Floor: 1, Load: 2, Target: 5},
		{Name: "med", PodMemBytes: 4 * gib, Floor: 1, Load: 1, Target: 4},
	}
	got := AllocateFleet(pools, 100*gib)

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
		{Name: "a", PodMemBytes: 16 * gib, Floor: 1, Load: 3, Target: 6},
		{Name: "b", PodMemBytes: 16 * gib, Floor: 1, Load: 2, Target: 5},
	}
	// Only 32 GiB usable — 2 pods — but real load wants 5 pods.
	got := AllocateFleet(pools, 32*gib)

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
		{Name: "busy", PodMemBytes: 8 * gib, Floor: 1, Load: 6, Target: 8},
		{Name: "idle", PodMemBytes: 8 * gib, Floor: 1, Load: 0, Target: 5},
	}
	// 64 GiB usable = 8 pods. busy load 6 (48 GiB). Floors: busy 0 (load
	// already > floor), idle 1 (8 GiB) → fit, 8 GiB left for headroom.
	// Headroom wants: busy 2, idle 4 (6 total). 1 pod split
	// proportionally → busy ~0, idle ~0 (rounding down). The point:
	// idle does NOT get its speculative 5; busy's real load is intact.
	got := AllocateFleet(pools, 64*gib)

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
		{Name: "small", PodMemBytes: 8 * gib, Floor: 20, Load: 0, Target: 25},
		// big: real queued load 10, no floor — pure demand.
		{Name: "big", PodMemBytes: 16 * gib, Floor: 0, Load: 10, Target: 10},
	}
	// 200 GiB usable. big's load = 160 GiB granted first, leaving 40 GiB
	// (5 pods of 8 GiB) for small's floor of 20 → squeezed to 5.
	got := AllocateFleet(pools, 200*gib)

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
		{Name: "x", PodMemBytes: 4 * gib, Floor: 1, Load: 0, Target: 5}, // wants 4 headroom
		{Name: "y", PodMemBytes: 4 * gib, Floor: 1, Load: 0, Target: 3}, // wants 2 headroom
	}
	// Floors: 2 pods = 8 GiB. Fleet 8 GiB base + 12 GiB (3 pods) left.
	// Headroom demand: x=4, y=2 (6 total). 3 pods split 2:1 → x≈2, y≈1.
	got := AllocateFleet(pools, 20*gib)

	if got["x"] != 3 { // floor 1 + 2 headroom
		t.Errorf("x = %d, want 3", got["x"])
	}
	if got["y"] != 2 { // floor 1 + 1 headroom
		t.Errorf("y = %d, want 2", got["y"])
	}
}

func TestAllocateFleet_NeverExceedsTarget(t *testing.T) {
	pools := []PoolDemand{
		{Name: "a", PodMemBytes: 1 * gib, Floor: 1, Load: 0, Target: 2},
	}
	got := AllocateFleet(pools, 1000*gib)
	if got["a"] != 2 {
		t.Errorf("a = %d, want 2 (capped at target)", got["a"])
	}
}

func TestAllocateFleet_ZeroCapacityHonorsLoadNotFloor(t *testing.T) {
	// No usable memory. Real load is still granted in full — it goes
	// Pending, the operator's "add a host" signal. A speculative floor
	// with no load behind it is NOT manufactured into Pending Pods, since
	// idle warm capacity yields to genuine demand.
	pools := []PoolDemand{
		{Name: "load", PodMemBytes: 4 * gib, Floor: 2, Load: 3, Target: 5},
		{Name: "floor", PodMemBytes: 4 * gib, Floor: 2, Load: 0, Target: 5},
	}
	got := AllocateFleet(pools, 0)
	if got["load"] != 3 {
		t.Errorf("load = %d, want 3 (real load honored even at zero capacity)", got["load"])
	}
	if got["floor"] != 0 {
		t.Errorf("floor = %d, want 0 (speculative floor squeezed, not left Pending)", got["floor"])
	}
}

func TestAllocateFleet_EmptyFleet(t *testing.T) {
	got := AllocateFleet(nil, 100*gib)
	if len(got) != 0 {
		t.Errorf("got %v, want empty", got)
	}
}
