package podagent

import (
	"strings"
	"testing"
)

// Tart's `--dir` accepts only `:ro` as a suffix; read-write is the default.
// A `:rw` suffix is a malformed mount tag and makes `tart run` exit 1, so the
// cache share must be mounted with no suffix.
func TestCacheShareMount_NoInvalidRWSuffix(t *testing.T) {
	got := cacheShareMount("/var/lib/tuist-runner-cache/vms/vm1/tuist-cache")
	if strings.HasSuffix(got, ":rw") {
		t.Fatalf("cache share mount must not use the invalid :rw suffix: %q", got)
	}
	want := RunnerCacheShareName + ":/var/lib/tuist-runner-cache/vms/vm1/tuist-cache"
	if got != want {
		t.Fatalf("cache share mount = %q, want %q", got, want)
	}
}
