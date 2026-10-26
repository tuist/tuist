package podagent

import (
	"errors"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"
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

// Per-host investigations need the volume a phase ran for; metrics must not.
func TestCustomCachePhaseLogsItsVolume(t *testing.T) {
	logs := captureLogs(t)
	slot := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", Scope: strings.Repeat("e", 64), BaseGeneration: 4, ManagedKey: "tuist-module"}, PodName: "runner-1", MountedGeneration: 3}
	cachevolumes.Observer(observeCustomCache).For(slot).Start("attach", "older")(nil)
	requireLogged(t, logs(), "cache phase", "scope="+slot.Scope, "use="+slot.ID, "kind=managed", "key=tuist-module", "generation=4", "mounted_generation=3", "pod=runner-1")
	if got := testutil.ToFloat64(customCacheOperations.WithLabelValues("attach", "older", "success")); got < 1 {
		t.Fatal("phase not counted under its bounded labels", got)
	}
}
