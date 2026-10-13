package cachevolumes

import "testing"

func TestCommitAcknowledgementCannotGrantOrIgnorePermissions(t *testing.T) {
	for _, mode := range []string{"true", "false", "invalid"} {
		if (Identity{CanPublish: true}).AcceptsCommit(mode) {
			t.Fatalf("legacy server accepted %s", mode)
		}
	}
	if !(Identity{}).AcceptsCommit("") || !(Identity{}).AcceptsCommit("auto") {
		t.Fatal("legacy auto request rejected")
	}
	if !(Identity{Commit: "true", CanPublish: false}).AcceptsCommit("true") {
		t.Fatal("denied writer cannot mount private clone")
	}
	if !(Identity{Commit: "false"}).AcceptsCommit("false") {
		t.Fatal("read-only request rejected")
	}
	if (Identity{Commit: "false", CanPublish: true}).AcceptsCommit("false") {
		t.Fatal("read-only request could publish")
	}
}

func TestCommitModeDefaultsOnlyAbsentMode(t *testing.T) {
	for input, want := range map[string]string{"": "auto", "auto": "auto", "true": "true", "false": "false", "invalid": "invalid"} {
		if got := CommitMode(input); got != want {
			t.Fatalf("%q: got %q want %q", input, got, want)
		}
	}
}
