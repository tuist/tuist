package main

import "testing"

func TestResolverRecordChanges(t *testing.T) {
	var state resolverRecordState
	for _, tc := range []struct {
		config         string
		readable, emit bool
	}{
		{"nameserver 10.0.0.1", true, true},
		{"nameserver 10.0.0.1", true, false},
		{"nameserver 10.0.0.2", true, true},
		{"", false, true}, {"", false, false}, {"", true, true},
	} {
		if state.changed(tc.config, tc.readable) != tc.emit {
			t.Fatalf("unexpected emission for %+v", tc)
		}
	}
}
