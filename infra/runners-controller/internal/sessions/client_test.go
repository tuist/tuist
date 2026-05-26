package sessions

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestClientStopped_Success(t *testing.T) {
	tokenPath := writeTempToken(t, "test-sa-token")

	called := false
	endedAt := time.Date(2026, 5, 26, 14, 23, 11, 0, time.UTC)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		if r.Method != http.MethodPost {
			t.Errorf("method = %s, want POST", r.Method)
		}
		if r.URL.Path != "/api/internal/runners/pods/stopped" {
			t.Errorf("path = %q, want /api/internal/runners/pods/stopped", r.URL.Path)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-sa-token" {
			t.Errorf("Authorization = %q, want Bearer test-sa-token", got)
		}
		if got := r.Header.Get("Content-Type"); got != "application/json" {
			t.Errorf("Content-Type = %q, want application/json", got)
		}

		body, _ := io.ReadAll(r.Body)
		var req StoppedRequest
		if err := json.Unmarshal(body, &req); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		if req.PodName != "tuist-macos-runner-pod-1" {
			t.Errorf("pod_name = %q, want tuist-macos-runner-pod-1", req.PodName)
		}
		if !req.EndedAt.Equal(endedAt) {
			t.Errorf("ended_at = %v, want %v", req.EndedAt, endedAt)
		}

		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	c := NewClient(server.URL + "/api/internal/runners")
	c.TokenPath = tokenPath

	if err := c.Stopped(context.Background(), "tuist-macos-runner-pod-1", endedAt); err != nil {
		t.Fatalf("Stopped: %v", err)
	}
	if !called {
		t.Error("server handler not called")
	}
}

func TestClientStopped_NonOK(t *testing.T) {
	tokenPath := writeTempToken(t, "test-sa-token")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "boom", http.StatusInternalServerError)
	}))
	defer server.Close()

	c := NewClient(server.URL + "/api/internal/runners")
	c.TokenPath = tokenPath

	err := c.Stopped(context.Background(), "pod-x", time.Now())
	if err == nil {
		t.Fatal("Stopped: expected error on 500, got nil")
	}
	if !strings.Contains(err.Error(), "HTTP 500") {
		t.Errorf("error = %v, want one mentioning HTTP 500", err)
	}
}

func TestClientStopped_MissingToken(t *testing.T) {
	c := NewClient("https://example.invalid/api/internal/runners")
	c.TokenPath = filepath.Join(t.TempDir(), "missing")

	err := c.Stopped(context.Background(), "pod-x", time.Now())
	if err == nil {
		t.Fatal("Stopped: expected error on missing token, got nil")
	}
}

func TestClientStopped_EmptyPodName(t *testing.T) {
	c := NewClient("https://example.invalid/api/internal/runners")
	err := c.Stopped(context.Background(), "", time.Now())
	if err == nil {
		t.Fatal("Stopped: expected error on empty pod name, got nil")
	}
}

func TestClientStopped_NoBaseURL(t *testing.T) {
	c := &Client{}
	err := c.Stopped(context.Background(), "pod-x", time.Now())
	if err == nil {
		t.Fatal("Stopped: expected error on empty base URL, got nil")
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
