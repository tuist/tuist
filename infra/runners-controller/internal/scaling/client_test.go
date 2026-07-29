package scaling

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestClientSignals_Success(t *testing.T) {
	tokenPath := writeTempToken(t, "test-sa-token")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer test-sa-token" {
			t.Errorf("Authorization header = %q, want Bearer test-sa-token", got)
		}
		if got := r.URL.Query().Get("fleet"); got != "linux-pool" {
			t.Errorf("fleet query = %q, want linux-pool", got)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(Signals{
			Fleet:                 "linux-pool",
			Claimed:               3,
			Queued:                2,
			P95ConcurrentLastHour: 5,
		})
	}))
	defer server.Close()

	c := NewClient(server.URL)
	c.TokenPath = tokenPath

	signals, err := c.Signals(context.Background(), "linux-pool")
	if err != nil {
		t.Fatalf("Signals: %v", err)
	}

	if signals.Fleet != "linux-pool" || signals.Claimed != 3 || signals.Queued != 2 || signals.P95ConcurrentLastHour != 5 {
		t.Errorf("Signals = %+v, want {linux-pool, 3, 2, 5}", signals)
	}
}

func TestClientSignals_NonOK(t *testing.T) {
	tokenPath := writeTempToken(t, "test-sa-token")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "service unavailable", http.StatusServiceUnavailable)
	}))
	defer server.Close()

	c := NewClient(server.URL)
	c.TokenPath = tokenPath

	_, err := c.Signals(context.Background(), "linux-pool")
	if err == nil {
		t.Fatal("Signals: expected error on 503, got nil")
	}
	if !strings.Contains(err.Error(), "HTTP 503") {
		t.Errorf("error = %v, want one mentioning HTTP 503", err)
	}
}

func TestClientSignals_MissingToken(t *testing.T) {
	c := NewClient("https://example.invalid")
	c.TokenPath = filepath.Join(t.TempDir(), "missing")

	_, err := c.Signals(context.Background(), "linux-pool")
	if err == nil {
		t.Fatal("Signals: expected error on missing token, got nil")
	}
}

func TestClientSignals_NoFleet(t *testing.T) {
	c := NewClient("https://example.invalid")
	_, err := c.Signals(context.Background(), "")
	if err == nil {
		t.Fatal("Signals: expected error on empty fleet, got nil")
	}
}

// countingSignalsServer returns an httptest server that counts how
// many times it was hit, echoing the requested fleet in the response.
func countingSignalsServer(t *testing.T, calls *int32) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(calls, 1)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(Signals{Fleet: r.URL.Query().Get("fleet"), Claimed: 1})
	}))
}

func TestClientSignals_CachesWithinTTL(t *testing.T) {
	tokenPath := writeTempToken(t, "test-sa-token")

	var calls int32
	server := countingSignalsServer(t, &calls)
	defer server.Close()

	c := NewClient(server.URL)
	c.TokenPath = tokenPath
	c.CacheTTL = time.Minute

	for i := 0; i < 3; i++ {
		if _, err := c.Signals(context.Background(), "linux-pool"); err != nil {
			t.Fatalf("Signals call %d: %v", i, err)
		}
	}

	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Errorf("server hit %d times, want 1 (TTL should serve repeats from cache)", got)
	}
}

func TestClientSignals_CachesPerFleet(t *testing.T) {
	tokenPath := writeTempToken(t, "test-sa-token")

	var calls int32
	server := countingSignalsServer(t, &calls)
	defer server.Close()

	c := NewClient(server.URL)
	c.TokenPath = tokenPath
	c.CacheTTL = time.Minute

	for _, fleet := range []string{"linux-a", "linux-a", "linux-b", "linux-b"} {
		if _, err := c.Signals(context.Background(), fleet); err != nil {
			t.Fatalf("Signals(%s): %v", fleet, err)
		}
	}

	// One miss per distinct fleet; the repeats hit the cache.
	if got := atomic.LoadInt32(&calls); got != 2 {
		t.Errorf("server hit %d times, want 2 (one per distinct fleet)", got)
	}
}

func TestClientSignals_NoCacheByDefault(t *testing.T) {
	tokenPath := writeTempToken(t, "test-sa-token")

	var calls int32
	server := countingSignalsServer(t, &calls)
	defer server.Close()

	// CacheTTL left at its 0 default — every call fetches.
	c := NewClient(server.URL)
	c.TokenPath = tokenPath

	for i := 0; i < 3; i++ {
		if _, err := c.Signals(context.Background(), "linux-pool"); err != nil {
			t.Fatalf("Signals call %d: %v", i, err)
		}
	}

	if got := atomic.LoadInt32(&calls); got != 3 {
		t.Errorf("server hit %d times, want 3 (caching disabled at TTL=0)", got)
	}
}

func writeTempToken(t *testing.T, token string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "token")
	if err := os.WriteFile(path, []byte(token), 0o600); err != nil {
		t.Fatalf("write token: %v", err)
	}
	return path
}
