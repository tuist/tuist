package metrics

import "testing"

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
