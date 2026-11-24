package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func sandboxCacheGrantJSON() map[string]any {
	return map[string]any{
		"id": "00000000-0000-0000-0000-0000000000c1", "scope": strings.Repeat("a", 64), "base_generation": 4,
		"image_digest": strings.Repeat("c", 40), "content_digest": strings.Repeat("b", 64),
	}
}

func requestSandboxCacheImage(t *testing.T, a *agent, ip, pod string, grant map[string]any) *httptest.ResponseRecorder {
	t.Helper()
	return postSandboxCacheImage(t, a, ip, map[string]any{"pod_name": pod, "grant": grant})
}

func requestSandboxCacheImageHolding(t *testing.T, a *agent, grant map[string]any, held []int64) *httptest.ResponseRecorder {
	t.Helper()
	return postSandboxCacheImage(t, a, "10.0.0.9", map[string]any{"pod_name": "sandboxd-x", "grant": grant, "held": held})
}

func postSandboxCacheImage(t *testing.T, a *agent, ip string, request map[string]any) *httptest.ResponseRecorder {
	t.Helper()
	body, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/sandbox-cache/image", bytes.NewReader(body))
	req.RemoteAddr = ip + ":1234"
	w := httptest.NewRecorder()
	a.serve(w, req)
	return w
}

// The agent streams the saved head it was named, as a sparse archive sandboxd
// can receive, only to this node's sandboxd, and keeps nothing afterwards.
func TestSandboxCacheImageStreamsTheNamedMaster(t *testing.T) {
	a, _ := sandboxAgent(t, checkoutGrantJSON(1), true)
	a.root = t.TempDir()
	master := filepath.Join(t.TempDir(), "master.img")
	f, err := os.Create(master)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.Truncate(64 << 20); err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteAt([]byte("ext4 cache contents"), 32<<20); err != nil {
		t.Fatal(err)
	}
	f.Close()
	var asked cachevolumes.Identity
	present, lent := true, int64(4)
	a.cloneMaster = func(_ context.Context, identity cachevolumes.Identity, dst string, held func(int64) bool) (int64, bool, error) {
		asked = identity
		if !present {
			return 0, false, cachevolumes.ErrNoMaster
		}
		if held(lent) {
			return lent, false, nil
		}
		data, err := os.ReadFile(master)
		if err != nil {
			return 0, false, err
		}
		return lent, true, os.WriteFile(dst, data, 0o600)
	}
	grant := sandboxCacheGrantJSON()

	if w := requestSandboxCacheImage(t, a, "10.0.0.10", "sandboxd-x", grant); w.Code != 403 || asked.Scope != "" {
		t.Fatalf("another address got %d and reached the master", w.Code)
	}
	bad := sandboxCacheGrantJSON()
	bad["id"] = "../x"
	if w := requestSandboxCacheImage(t, a, "10.0.0.9", "sandboxd-x", bad); w.Code != 400 {
		t.Fatalf("an invalid use got %d", w.Code)
	}

	w := requestSandboxCacheImage(t, a, "10.0.0.9", "sandboxd-x", grant)
	if w.Code != 200 || w.Header().Get(sandboxCacheGeneration) != "4" {
		t.Fatalf("copy: %d %s, generation %q", w.Code, w.Body, w.Header().Get(sandboxCacheGeneration))
	}
	if asked.Scope != grant["scope"] || asked.BaseGeneration != 4 || asked.ContentDigest != grant["content_digest"] || asked.ImageDigest != grant["image_digest"] {
		t.Fatalf("the agent cloned %+v, not the granted head", asked)
	}
	received := filepath.Join(t.TempDir(), "received.img")
	if err := cachevolumes.ReceiveImage(context.Background(), w.Body, received, 64<<20); err != nil {
		t.Fatal(err)
	}
	want, _ := os.ReadFile(master)
	if got, _ := os.ReadFile(received); !bytes.Equal(got, want) {
		t.Fatal("sandboxd received other bytes than the master's")
	}
	if entries, _ := os.ReadDir(filepath.Join(a.root, sandboxCacheDir)); len(entries) != 0 {
		t.Fatalf("the agent kept %d clones", len(entries))
	}

	// A node that kept only an older master lends it and names it; a caller
	// that already holds that generation gets no second copy.
	lent = 2
	if w := requestSandboxCacheImage(t, a, "10.0.0.9", "sandboxd-x", grant); w.Code != 200 || w.Header().Get(sandboxCacheGeneration) != "2" {
		t.Fatalf("an older master answered %d, generation %q", w.Code, w.Header().Get(sandboxCacheGeneration))
	}
	if w := requestSandboxCacheImageHolding(t, a, grant, []int64{1, 2}); w.Code != 204 || w.Header().Get(sandboxCacheGeneration) != "2" || w.Body.Len() != 0 {
		t.Fatalf("a caller holding the lent generation got %d, generation %q, %d bytes", w.Code, w.Header().Get(sandboxCacheGeneration), w.Body.Len())
	}
	if entries, _ := os.ReadDir(filepath.Join(a.root, sandboxCacheDir)); len(entries) != 0 {
		t.Fatalf("the agent kept %d clones", len(entries))
	}

	present = false
	if w := requestSandboxCacheImage(t, a, "10.0.0.9", "sandboxd-x", grant); w.Code != 404 || answerError(w) != "cold" {
		t.Fatalf("a node without the master answered %d %s", w.Code, w.Body)
	}
	a.cloneMaster = nil
	if w := requestSandboxCacheImage(t, a, "10.0.0.9", "sandboxd-x", grant); w.Code != 503 {
		t.Fatalf("an agent without local images answered %d", w.Code)
	}
}
