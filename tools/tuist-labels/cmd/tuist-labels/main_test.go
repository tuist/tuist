package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
)

func TestWorkflowAndExclusiveCredentials(t *testing.T) {
	var submitted struct {
		Items []struct {
			Text string `json:"text"`
		} `json:"items"`
		Width  float64 `json:"widthMm"`
		Height float64 `json:"heightMm"`
	}
	creations := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/api/sessions" {
			creations++
			fmt.Fprint(w, `{"id":"session-1","controlToken":"private-control","relayToken":"private-relay","expiresAt":9999999999999}`)
			return
		}
		if r.Header.Get("Authorization") != "Bearer private-control" {
			t.Error("missing scoped authorization")
		}
		if strings.HasSuffix(r.URL.Path, "/jobs") {
			if err := json.NewDecoder(r.Body).Decode(&submitted); err != nil {
				t.Error(err)
			}
			fmt.Fprint(w, `{"queued":2,"state":"preview-only"}`)
			return
		}
		fmt.Fprint(w, `{"printingEnabled":false,"jobs":[]}`)
	}))
	defer server.Close()
	dir := t.TempDir()
	var out bytes.Buffer
	c := client{http: server.Client(), out: &out, file: filepath.Join(dir, "session.json")}
	if err := c.run([]string{"init", server.URL, "https://labels.example.com"}); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "https://labels.example.com/relay#") || strings.Contains(out.String(), "?token=") {
		t.Fatal("links must use fragments and browser origin")
	}
	info, _ := os.Stat(c.file)
	if info.Mode().Perm() != 0600 {
		t.Fatal("credentials must be private")
	}
	if err := c.run([]string{"init", server.URL}); err == nil || creations != 1 {
		t.Fatal("init must not overwrite or create a second session")
	}
	file := filepath.Join(dir, "labels.txt")
	_ = os.WriteFile(file, []byte("R02-SW01\r\n\r\nR02-P09\n"), 0600)
	if err := c.run([]string{"submit-text", file, "38.1", "10"}); err != nil {
		t.Fatal(err)
	}
	if len(submitted.Items) != 2 || submitted.Items[0].Text != "R02-SW01" || submitted.Items[1].Text != "R02-P09" || submitted.Width != 38.1 || submitted.Height != 10 {
		t.Fatalf("incorrect submission: %+v", submitted)
	}
	if err := c.run([]string{"status"}); err != nil {
		t.Fatal(err)
	}
}

func TestRejectsUnsafeOrigins(t *testing.T) {
	for _, raw := range []string{"http://remote.example", "https://user:pass@example.com", "https://example.com/path", "https://example.com/?token=x", "https://example.com/#secret", "file:///tmp/socket"} {
		if _, err := origin(raw, false); err == nil {
			t.Errorf("accepted %s", raw)
		}
	}
	if _, err := origin("http://localhost:3077", true); err == nil {
		t.Fatal("browser override must require HTTPS")
	}
}

func TestOutputDoesNotRetryAfterLostResponse(t *testing.T) {
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		conn, _, err := w.(http.Hijacker).Hijack()
		if err != nil {
			t.Error(err)
			return
		}
		conn.Close()
	}))
	defer server.Close()
	c := client{http: server.Client()}
	_, err := c.request(session{Base: server.URL, ControlToken: "control"}, "/api/sessions/test/print", "POST", map[string]string{"jobId": "one"})
	if err == nil || requests.Load() != 1 {
		t.Fatalf("output retried or unknown outcome hidden: calls=%d error=%v", requests.Load(), err)
	}
}
