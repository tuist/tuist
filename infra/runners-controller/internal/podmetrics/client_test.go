package podmetrics

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func writeTempToken(t *testing.T, token string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(path, []byte(token), 0o600); err != nil {
		t.Fatalf("write token: %v", err)
	}
	return path
}

func TestReport_Success(t *testing.T) {
	var (
		called bool
		gotReq metricsRequest
	)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		if r.Method != http.MethodPost {
			t.Errorf("method = %s, want POST", r.Method)
		}
		if r.URL.Path != "/api/internal/runners/pods/runner-pod-1/metrics" {
			t.Errorf("path = %s", r.URL.Path)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer sa-token" {
			t.Errorf("authorization = %q", got)
		}
		if err := json.NewDecoder(r.Body).Decode(&gotReq); err != nil {
			t.Errorf("decode body: %v", err)
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	c := NewClient(server.URL + "/api/internal/runners")
	c.TokenPath = writeTempToken(t, "sa-token")

	samples := []Sample{{Timestamp: 1_750_000_000.0, CPUUsagePercent: 42.5, MemoryUsedBytes: 1024}}
	if err := c.Report(context.Background(), "runner-pod-1", samples); err != nil {
		t.Fatalf("Report: %v", err)
	}
	if !called {
		t.Fatal("server handler not called")
	}
	if len(gotReq.Samples) != 1 || gotReq.Samples[0].CPUUsagePercent != 42.5 {
		t.Errorf("decoded samples = %+v", gotReq.Samples)
	}
}

func TestReport_EmptyBatchSkipsRequest(t *testing.T) {
	called := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	c := NewClient(server.URL + "/api/internal/runners")
	c.TokenPath = writeTempToken(t, "sa-token")

	if err := c.Report(context.Background(), "runner-pod-1", nil); err != nil {
		t.Fatalf("Report: %v", err)
	}
	if called {
		t.Error("server called for an empty batch; want skipped")
	}
}

func TestReport_Non2xxIsError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()

	c := NewClient(server.URL + "/api/internal/runners")
	c.TokenPath = writeTempToken(t, "sa-token")

	err := c.Report(context.Background(), "runner-pod-1", []Sample{{Timestamp: 1.0}})
	if err == nil {
		t.Fatal("expected error on 503")
	}
}
