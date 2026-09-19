package scaling

import "testing"

func TestDesiredReplicas(t *testing.T) {
	tests := []struct {
		name    string
		signals Signals
		knobs   PolicyKnobs
		want    int32
	}{
		{
			name:    "max=0 disables autoscaling",
			signals: Signals{Claimed: 5, Queued: 3, P95ConcurrentLastHour: 4},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 2, MaxReplicas: 0},
			want:    0,
		},
		{
			name:    "idle with p95 history keeps warm floor at p95 + slack",
			signals: Signals{Claimed: 0, Queued: 0, P95ConcurrentLastHour: 5},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 1, MaxReplicas: 30},
			want:    6, // floor=5 (p95), target=max(0,5)=5, desired=5+1=6
		},
		{
			name:    "idle with no history uses MinWarmPoolFloor",
			signals: Signals{Claimed: 0, Queued: 0, P95ConcurrentLastHour: 0},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 3, MaxReplicas: 30},
			want:    3, // target=max(0,0)=0, desired=0+3=3
		},
		{
			name:    "MinWarmPoolFloor is not double-counted when it exceeds p95",
			signals: Signals{Claimed: 0, Queued: 0, P95ConcurrentLastHour: 1},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 3, MaxReplicas: 30},
			want:    4, // target=max(0,1)=1, desired=1+3=4
		},
		{
			name:    "steady load matching p95",
			signals: Signals{Claimed: 5, Queued: 0, P95ConcurrentLastHour: 5},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 1, MaxReplicas: 30},
			want:    6, // floor=5, target=max(5,5)=5, desired=5+1=6
		},
		{
			name:    "ramp-up above p95 grows target",
			signals: Signals{Claimed: 8, Queued: 3, P95ConcurrentLastHour: 5},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 1, MaxReplicas: 30},
			want:    12, // floor=5, target=max(11,5)=11, desired=11+1=12
		},
		{
			name:    "post-job occupancy stays in real load after its claim ends",
			signals: Signals{Claimed: 1, Occupied: 3, Queued: 2, P95ConcurrentLastHour: 0},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 1, MaxReplicas: 30},
			want:    6,
		},
		{
			name:    "peak inbound beyond claimed",
			signals: Signals{Claimed: 0, Queued: 10, P95ConcurrentLastHour: 5},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 1, MaxReplicas: 30},
			want:    11, // floor=5, target=max(10,5)=10, desired=10+1=11
		},
		{
			name:    "MaxReplicas caps the result",
			signals: Signals{Claimed: 25, Queued: 10, P95ConcurrentLastHour: 5},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 2, MaxReplicas: 20},
			want:    20,
		},
		{
			name:    "MinWarmPoolFloor below 1 still yields the slack",
			signals: Signals{Claimed: 0, Queued: 0, P95ConcurrentLastHour: 0},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 0, MaxReplicas: 30},
			want:    0, // floor=0, target=0, desired=0+0=0
		},
		// The incident: a pool whose only work is blocked on the
		// account's concurrency limit used to report load 0, read as
		// idle, and win nothing on a saturated fleet. It must ask for
		// one Pod even with no floor and no p95 history behind it.
		{
			name:    "withheld work alone is demand for one Pod",
			signals: Signals{Claimed: 0, Occupied: 0, Queued: 0, Withheld: 1, P95ConcurrentLastHour: 0},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 0, MaxReplicas: 30},
			want:    1, // load=0+0+1=1, target=max(1,0)=1, desired=1+0=1
		},
		{
			name:    "withheld demand saturates at one Pod",
			signals: Signals{Claimed: 0, Occupied: 0, Queued: 0, Withheld: 40, P95ConcurrentLastHour: 0},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 0, MaxReplicas: 30},
			want:    1, // NOT 40 — sizing for the full withheld count is the
			// idle-Pod squatting the withholding exists to prevent.
		},
		{
			name:    "withheld adds at most one Pod on top of dispatchable work",
			signals: Signals{Claimed: 4, Occupied: 4, Queued: 2, Withheld: 9, P95ConcurrentLastHour: 0},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 1, MaxReplicas: 30},
			want:    8, // load=4+2+1=7, target=max(7,0)=7, desired=7+1=8
		},
		// Rolling-deploy safety: an older server omits `withheld`, it
		// decodes to zero, and the result is byte-for-byte today's.
		{
			name:    "older server omitting withheld behaves exactly as before",
			signals: Signals{Claimed: 8, Occupied: 8, Queued: 3, P95ConcurrentLastHour: 5},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 1, MaxReplicas: 30},
			want:    12, // identical to "ramp-up above p95 grows target"
		},
		{
			name:    "withheld does not lift a pool already capped at MaxReplicas",
			signals: Signals{Claimed: 30, Occupied: 30, Queued: 0, Withheld: 5, P95ConcurrentLastHour: 0},
			knobs:   PolicyKnobs{MinWarmPoolFloor: 1, MaxReplicas: 30},
			want:    30,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := DesiredReplicas(tc.signals, tc.knobs)
			if got != tc.want {
				t.Errorf("DesiredReplicas(%+v, %+v) = %d, want %d", tc.signals, tc.knobs, got, tc.want)
			}
		})
	}
}
