package main

import (
	"reflect"
	"strconv"
	"testing"
)

func TestBoundedGroupsKeepsPrimaryAndFitsNGroupsMax(t *testing.T) {
	// The runner user on macOS 26.6 images: primary staff (20) plus 16 more,
	// one past what setgroups(2) accepts.
	ids := []string{"12", "20", "61", "79", "80", "81", "98", "33", "100", "204", "250", "395", "398", "399", "400", "701", "702"}

	got := boundedGroups(20, ids)

	if len(got) != 16 {
		t.Fatalf("got %d groups, want 16: %v", len(got), got)
	}
	want := []uint32{20, 12, 33, 61, 79, 80, 81, 98, 100, 204, 250, 395, 398, 399, 400, 701}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func TestBoundedGroupsKeepsAHighPrimaryGroup(t *testing.T) {
	ids := []string{"5000"}
	for gid := 1; gid <= 20; gid++ {
		ids = append(ids, strconv.Itoa(gid))
	}

	got := boundedGroups(5000, ids)

	if len(got) != 16 || got[0] != 5000 {
		t.Fatalf("primary group dropped or limit exceeded: %v", got)
	}
}
