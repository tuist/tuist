package podagent

import (
	"errors"
	"strings"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// A failed phase used to log only its result category, so a clone that failed
// in 10µs on staging left nothing to diagnose it with.
func TestCustomCachePhaseLogsTheFailure(t *testing.T) {
	logs := captureLogs(t)
	observeCustomCache(cachevolumes.Observation{Operation: "clone", Source: "local", Err: errors.New("cp operation failed: exit status 1")})
	observeCustomCache(cachevolumes.Observation{Operation: "attach", Source: "local"})
	got := logs()
	if len(got) != 2 {
		t.Fatal(got)
	}
	if !strings.Contains(got[0], "result=error") || !strings.Contains(got[0], "error=cp operation failed: exit status 1") {
		t.Fatalf("failure logged without its error: %s", got[0])
	}
	if strings.Contains(got[1], "error=") {
		t.Fatalf("success logged an error: %s", got[1])
	}
}
