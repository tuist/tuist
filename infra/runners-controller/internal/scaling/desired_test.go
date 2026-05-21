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
			want:    6, // floor=3 (no p95), target=max(0,3)=3, desired=3+3=6
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
