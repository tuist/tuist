package scaling

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
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

func writeTempToken(t *testing.T, token string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "token")
	if err := os.WriteFile(path, []byte(token), 0o600); err != nil {
		t.Fatalf("write token: %v", err)
	}
	return path
}
