package main

import (
	"bytes"
	"encoding/base64"
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

const testSessionID = "12345678-1234-4567-89ab-123456789abc"

func TestWorkflowAndExclusiveCredentials(t *testing.T) {
	t.Setenv("ATLAS_TOKEN", "atlas-oauth-secret")
	png, err := base64.StdEncoding.DecodeString("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")
	if err != nil {
		t.Fatal(err)
	}
	var submitted struct {
		Items []struct {
			Text string `json:"text"`
			PNG  string `json:"png"`
		} `json:"items"`
		Width  float64 `json:"widthMm"`
		Height float64 `json:"heightMm"`
	}
	creations := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		wantToken := "Bearer atlas-oauth-secret"
		if strings.HasSuffix(r.URL.Path, ".png") {
			wantToken = "Bearer rotated-preview-token"
		}
		if r.Header.Get("Authorization") != wantToken {
			t.Error("missing Atlas OAuth authorization")
		}
		if r.URL.Path == "/api/labels/sessions" && r.Method == http.MethodPost {
			creations++
			fmt.Fprintf(w, `{"id":%q,"relayToken":"private-relay","expiresAt":9999999999999}`, testSessionID)
			return
		}
		if r.URL.Path == "/api/labels/sessions/"+testSessionID+"/jobs/job-1.png" && r.Method == http.MethodGet {
			w.Header().Set("Content-Type", "image/png")
			_, _ = w.Write(png)
			return
		}
		if r.URL.Path == "/api/labels/sessions/"+testSessionID+"/jobs" && r.Method == http.MethodPost {
			if err := json.NewDecoder(r.Body).Decode(&submitted); err != nil {
				t.Error(err)
			}
			fmt.Fprint(w, `{"queued":2,"state":"preview-only"}`)
			return
		}
		if r.URL.Path != "/api/labels/sessions/"+testSessionID && !strings.HasSuffix(r.URL.Path, "/not-an-image.png") {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		fmt.Fprint(w, `{"printingEnabled":false,"jobs":[]}`)
	}))
	defer server.Close()
	dir := t.TempDir()
	var out bytes.Buffer
	c := client{http: server.Client(), out: &out, file: filepath.Join(dir, "session.json")}
	if err := c.run([]string{"init", server.URL}); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), server.URL+"/operations/labels/"+testSessionID+"#token=private-relay") || strings.Contains(out.String(), "?token=") {
		t.Fatal("links must use fragments and the same Atlas origin")
	}
	state, err := os.ReadFile(c.file)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(out.String(), "atlas-oauth-secret") || bytes.Contains(state, []byte("atlas-oauth-secret")) || bytes.Contains(state, []byte("controlToken")) || bytes.Contains(state, []byte("browserBase")) {
		t.Fatal("Atlas bearer credentials must not be printed or persisted")
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
	image := filepath.Join(dir, "input.png")
	if err := os.WriteFile(image, png, 0600); err != nil {
		t.Fatal(err)
	}
	if err := c.run([]string{"submit-png", image}); err != nil {
		t.Fatal(err)
	}
	if len(submitted.Items) != 1 || submitted.Items[0].PNG != base64.StdEncoding.EncodeToString(png) {
		t.Fatal("PNG submission must preserve the base64 items contract")
	}
	t.Setenv("ATLAS_TOKEN", "rotated-preview-token")
	preview := filepath.Join(dir, "preview.png")
	if err := c.run([]string{"preview", "job-1", preview}); err != nil {
		t.Fatal(err)
	}
	saved, err := os.ReadFile(preview)
	if err != nil || !bytes.Equal(saved, png) {
		t.Fatal("preview must save the actual server image")
	}
	if err := c.run([]string{"preview", "job-1", preview}); err == nil {
		t.Fatal("preview must not overwrite an existing file")
	}
	if err := c.run([]string{"preview", "not-an-image", filepath.Join(dir, "bad.png")}); err == nil {
		t.Fatal("preview must reject a JSON response instead of saving it as an image")
	}
}

func TestRejectsUnsafeOrigins(t *testing.T) {
	for _, raw := range []string{"http://remote.example", "https://user:pass@example.com", "https://example.com/path", "https://example.com/?token=x", "https://example.com/#secret", "file:///tmp/socket"} {
		if _, err := origin(raw, false); err == nil {
			t.Errorf("accepted %s", raw)
		}
	}
}

func TestOutputDoesNotRetryAfterLostResponse(t *testing.T) {
	t.Setenv("ATLAS_TOKEN", "atlas-token")
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
	_, err := c.request(session{Base: server.URL}, "/api/labels/sessions/"+testSessionID+"/print", "POST", map[string]string{"jobId": "one"})
	if err == nil || requests.Load() != 1 {
		t.Fatalf("output retried or unknown outcome hidden: calls=%d error=%v", requests.Load(), err)
	}
}

func saveTestSession(t *testing.T, file, base string) {
	t.Helper()
	b, err := json.Marshal(session{ID: testSessionID, RelayToken: "relay-secret", ExpiresAt: 9999999999999, Base: base})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, b, 0600); err != nil {
		t.Fatal(err)
	}
}

func TestPendingApprovalAndFreshBearer(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := calls.Add(1)
		if r.Header.Get("Authorization") != fmt.Sprintf("Bearer token-%d", n) {
			t.Error("each call must read the current ATLAS_TOKEN")
		}
		w.Header().Set("Content-Type", "application/json")
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if r.Method != http.MethodPost {
			t.Errorf("unexpected method %s", r.Method)
		}
		switch r.URL.Path {
		case "/api/labels/sessions/" + testSessionID + "/print":
			if len(body) != 1 || body["jobId"] != "exact-job" {
				t.Errorf("print must only request the exact job: %v", body)
			}
		case "/api/labels/sessions/" + testSessionID + "/cut":
			if len(body) != 0 {
				t.Errorf("cut must send an empty object, not authorization: %v", body)
			}
		default:
			t.Errorf("unexpected endpoint %s", r.URL.Path)
		}
		fmt.Fprint(w, `{"jobId":"exact-job","state":"awaiting-approval","approvalUrl":"https://atlas.example.com/operations/labels/approval"}`)
	}))
	defer server.Close()
	var out bytes.Buffer
	c := client{http: server.Client(), out: &out, file: filepath.Join(t.TempDir(), "session.json")}
	saveTestSession(t, c.file, server.URL)
	for i, args := range [][]string{{"print-one", "exact-job"}, {"cut-once"}} {
		t.Setenv("ATLAS_TOKEN", fmt.Sprintf("token-%d", i+1))
		out.Reset()
		if err := c.run(args); err != nil {
			t.Fatal(err)
		}
		var result map[string]string
		if err := json.Unmarshal(out.Bytes(), &result); err != nil || len(result) != 3 || result["state"] != "awaiting-approval" || result["jobId"] != "exact-job" || result["approvalUrl"] != "https://atlas.example.com/operations/labels/approval" {
			t.Fatalf("must return the pending browser approval unchanged: %s (%v)", out.String(), err)
		}
	}
	if calls.Load() != 2 {
		t.Fatal("must not approve or automatically retry")
	}
}

func TestMissingTokenAndLegacySessions(t *testing.T) {
	t.Setenv("ATLAS_TOKEN", "")
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		t.Error("must reject locally without an API call")
	}))
	defer server.Close()
	dir := t.TempDir()
	input := filepath.Join(dir, "label.txt")
	if err := os.WriteFile(input, []byte("label"), 0600); err != nil {
		t.Fatal(err)
	}
	commands := [][]string{{"init", server.URL}, {"links"}, {"status"}, {"preview", "job", filepath.Join(dir, "preview.png")}, {"print-one", "job"}, {"cut-once"}, {"submit-text", input}, {"submit-png", input}}
	for _, legacy := range []bool{false, true} {
		for _, args := range commands {
			t.Run(fmt.Sprintf("legacy=%t/%s", legacy, args[0]), func(t *testing.T) {
				var out bytes.Buffer
				c := client{http: server.Client(), out: &out, file: filepath.Join(t.TempDir(), "session.json")}
				if legacy {
					b := []byte(`{"id":"old-session","controlToken":"legacy-secret","relayToken":"old-relay","browserBase":"https://old.example"}`)
					if err := os.WriteFile(c.file, b, 0600); err != nil {
						t.Fatal(err)
					}
					marker := filepath.Join(filepath.Dir(c.file), "dispatch-marker")
					if err := os.WriteFile(marker, []byte("preserve"), 0600); err != nil {
						t.Fatal(err)
					}
					err := c.run(args)
					if err == nil || !strings.Contains(err.Error(), "legacy") || !strings.Contains(err.Error(), "M211_STATE_DIR") || !strings.Contains(err.Error(), "ATLAS_TOKEN") || strings.Contains(err.Error(), "legacy-secret") {
						t.Fatalf("expected safe migration guidance: %v", err)
					}
					after, err := os.ReadFile(c.file)
					if err != nil || !bytes.Equal(after, b) {
						t.Fatal("legacy credentials must remain untouched")
					}
					if after, err := os.ReadFile(marker); err != nil || string(after) != "preserve" {
						t.Fatal("legacy dispatch markers must remain untouched")
					}
					return
				}
				if args[0] != "init" {
					saveTestSession(t, c.file, server.URL)
				}
				err := c.run(args)
				if args[0] == "links" {
					if err != nil {
						t.Fatal("local links do not require an API token:", err)
					}
				} else if err == nil || !strings.Contains(err.Error(), "ATLAS_TOKEN") {
					t.Fatalf("expected missing token guidance: %v", err)
				}
				if args[0] == "init" {
					if _, err := os.Stat(c.file); !os.IsNotExist(err) {
						t.Fatal("missing token must not leave session state")
					}
				}
			})
		}
	}
	if calls.Load() != 0 {
		t.Fatalf("unexpected calls: %d", calls.Load())
	}
}

func TestInitRejectsSeparateBrowserOriginAndInvalidResponse(t *testing.T) {
	t.Setenv("ATLAS_TOKEN", "atlas-token")
	for _, response := range []string{
		`{"id":"not-a-uuid","relayToken":"secret","expiresAt":9999999999999}`,
		`{"id":"12345678-1234-4567-89ab-123456789abc","relayToken":"secret"}`,
		`{"id":"12345678-1234-4567-89ab-123456789abc","relayToken":"secret","expiresAt":9999999999999,"controlToken":"legacy"}`,
	} {
		t.Run(response, func(t *testing.T) {
			var calls atomic.Int32
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				w.Header().Set("Content-Type", "application/json")
				fmt.Fprint(w, response)
			}))
			defer server.Close()
			var out bytes.Buffer
			c := client{http: server.Client(), out: &out, file: filepath.Join(t.TempDir(), "session.json")}
			if err := c.run([]string{"init", server.URL, "https://browser.example.com"}); err == nil || calls.Load() != 0 {
				t.Fatal("init must reject a separate browser origin before any API call")
			}
			if err := c.run([]string{"init", server.URL}); err == nil || calls.Load() != 1 {
				t.Fatal("init must reject invalid response without retries")
			}
			if _, err := os.Stat(c.file); !os.IsNotExist(err) {
				t.Fatal("invalid response must not leave usable session state")
			}
		})
	}
}
