package controllers

import (
	"testing"
)

func TestRollConcurrencyCap(t *testing.T) {
	cases := []struct {
		name     string
		replicas int32
		pct      int32
		want     int
	}{
		{"9 hosts at 5% floors to the minimum of 1", 9, 5, 1},
		{"20 at 5% is exactly 1", 20, 5, 1},
		{"21 at 5% still floors to 1", 21, 5, 1},
		{"40 at 5% is 2", 40, 5, 2},
		{"100 at 5% is 5", 100, 5, 5},
		{"40 at 10% is 4", 40, 10, 4},
		{"sub-1 share floors up to the minimum of 1", 10, 5, 1},
		{"zero replicas yields the minimum of 1", 0, 5, 1},
		{"negative replicas yields the minimum of 1", -3, 5, 1},
		{"zero percent yields the minimum of 1", 9, 0, 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := rollConcurrencyCap(tc.replicas, tc.pct); got != tc.want {
				t.Fatalf("rollConcurrencyCap(%d, %d) = %d, want %d", tc.replicas, tc.pct, got, tc.want)
			}
		})
	}
}
