package main

import "testing"

func TestParseSize(t *testing.T) {
	for in, want := range map[string]int64{"600G": 600 << 30, "1g": 1 << 30, "64M": 64 << 20, "2TiB": 2 << 40} {
		if got, err := parseSize(in); err != nil || got != want {
			t.Fatalf("%s = %d %v", in, got, err)
		}
	}
	for _, in := range []string{"", "600", "1.5G", "-1G", "0G", "1K", "2048T"} {
		if _, err := parseSize(in); err == nil {
			t.Fatalf("accepted %q", in)
		}
	}
}
