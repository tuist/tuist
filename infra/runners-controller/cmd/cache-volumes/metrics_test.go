package main

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func TestVolumeMetricsClassifyCancellationWithoutLeakingErrors(t *testing.T) {
	var logs bytes.Buffer
	m := newVolumeMetrics(slog.New(slog.NewJSONHandler(&logs, nil)), 40_000_000_000)
	m.observe(cachevolumes.Observation{Operation: "attach", Source: "remote", Duration: 25 * time.Second, Err: errors.Join(context.DeadlineExceeded, errors.New("https://signed-url?secret=private"))})
	m.observe(cachevolumes.Observation{Operation: "attach", Source: "local", Duration: time.Second})
	m.observe(cachevolumes.Observation{Operation: "maintenance", Source: "none"})
	r := httptest.NewRecorder()
	m.handler().ServeHTTP(r, httptest.NewRequest("GET", "/metrics", nil))
	for _, want := range []string{`tuist_runner_cache_volume_operations_total{operation="attach",result="timeout",source="remote"} 1`, `tuist_runner_cache_volume_operations_total{operation="attach",result="success",source="local"} 1`, `tuist_runner_cache_volume_operation_duration_seconds_sum{operation="attach",source="remote"} 25`} {
		if !strings.Contains(r.Body.String(), want) {
			t.Fatalf("missing %s in %s", want, r.Body.String())
		}
	}
	if strings.Contains(logs.String(), "private") || strings.Contains(r.Body.String(), "private") {
		t.Fatal("leaked signed URL")
	}
	if !strings.Contains(logs.String(), `"result":"timeout"`) || strings.Contains(logs.String(), `"operation":"maintenance"`) {
		t.Fatal(logs.String())
	}
}

func TestVolumeMetricsLogTheCauseWithoutSignedURLs(t *testing.T) {
	var logs bytes.Buffer
	m := newVolumeMetrics(slog.New(slog.NewJSONHandler(&logs, nil)), 40_000_000_000)
	m.observe(cachevolumes.Observation{Operation: "maintenance", Source: "none", Err: errors.Join(errors.New("umount: target is busy"), errors.New(`Put "https://storage.example/image?X-Amz-Signature=private": EOF`))})
	if !strings.Contains(logs.String(), `"error":"umount: target is busy\nPut \"<url>\": EOF"`) || strings.Contains(logs.String(), "private") {
		t.Fatal(logs.String())
	}
	logs.Reset()
	m.observe(cachevolumes.Observation{Operation: "publish", Source: "none", Err: cachevolumes.ErrReleasePending})
	if !strings.Contains(logs.String(), `"level":"INFO"`) || !strings.Contains(logs.String(), `"result":"release_pending"`) {
		t.Fatal(logs.String())
	}
}
