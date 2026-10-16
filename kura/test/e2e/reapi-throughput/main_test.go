package main

import "testing"

func TestWorkloadBounds(t *testing.T) {
	maxInt := int(^uint(0) >> 1)
	for _, tt := range []struct {
		name                                              string
		size, count, workers, connections, passes, rounds int
		valid                                             bool
	}{
		{"small-primary", 4096, 4096, 32, 4, 8, 1, true},
		{"medium-primary", 65536, 1024, 32, 4, 8, 1, true},
		{"large-primary", 1 << 20, 256, 32, 4, 8, 1, true},
		{"largest-primary", 8 << 20, 32, 32, 4, 8, 1, true},
		{"holdout", 384 << 10, 512, 512, 4, 8, 16, true},
		{"payload-ceiling", 1 << 20, 512, 4, 4, 8, 1, true},
		{"zero-size", 0, 1024, 32, 4, 8, 1, false},
		{"negative-count", 65536, -1, 32, 4, 8, 1, false},
		{"zero-workers", 65536, 1024, 0, 4, 8, 1, false},
		{"zero-connections", 65536, 1024, 32, 0, 8, 1, false},
		{"zero-passes", 65536, 1024, 32, 4, 0, 1, false},
		{"zero-rounds", 65536, 1024, 32, 4, 8, 0, false},
		{"payload-overflow", maxInt, 4, 32, 4, 8, 1, false},
		{"count-overflow", 8, maxInt, 32, 4, 8, 1, false},
		{"passes-overflow", 1, 4, 32, 4, maxInt, 1, false},
		{"rounds-overflow", 1, 4, 32, 4, 1, maxInt, false},
		{"retained-ceiling", 1, 512, 32, 4, 1, 2048, true},
		{"retained-over-ceiling", 1, 512, 32, 4, 1, 2049, false},
		{"too-many-records", 1, (1 << 20) + 1, 32, 4, 8, 1, false},
		{"too-many-workers", 65536, 1024, 4097, 4, 8, 1, false},
		{"too-many-connections", 65536, 1024, 32, 1025, 8, 1, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			err := validateWorkload(tt.size, tt.count, tt.workers, tt.connections, tt.passes, tt.rounds)
			if (err == nil) != tt.valid {
				t.Fatalf("valid=%v, error=%v", tt.valid, err)
			}
		})
	}
}
