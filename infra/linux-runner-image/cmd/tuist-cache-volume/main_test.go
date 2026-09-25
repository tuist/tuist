package main

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestColdFallbackPreservesExistingContent(t *testing.T) {
	t.Setenv("TUIST_CACHE_VOLUME_URL", "")
	root := t.TempDir()
	path := filepath.Join(root, ".gradle/caches/modules-2")
	if err := attach("gradle", []string{path}); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(path, "dependency"), []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := attach("gradle", []string{path}); err == nil {
		t.Fatal("replaced nonempty directory")
	}
	if b, err := os.ReadFile(filepath.Join(path, "dependency")); err != nil || string(b) != "keep" {
		t.Fatal("lost content")
	}
}
func TestRejectSymlinkTargets(t *testing.T) {
	root := t.TempDir()
	target := filepath.Join(root, "symlink")
	if err := os.Symlink(t.TempDir(), target); err != nil {
		t.Fatal(err)
	}
	if err := emptyTarget(target); err == nil {
		t.Fatal("accepted symlink")
	}
}
func TestHTTPFailureDoesNotDecodeOrRedirect(t *testing.T) {
	hit := false
	destination := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { hit = true }))
	defer destination.Close()
	redirect := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, destination.URL, 302) }))
	defer redirect.Close()
	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	req, _ := http.NewRequest("GET", redirect.URL, nil)
	var result any
	if err := requestJSON(client, req, &result); err == nil {
		t.Fatal("accepted redirect")
	}
	if hit {
		t.Fatal("sent credential to redirect target")
	}
}

func TestAttachInContainerNamespaceWithoutWorkflowCredentials(t *testing.T) {
	root := t.TempDir()
	workspace := filepath.Join(root, "__w/repo/repo")
	cache := filepath.Join(root, "__w/_tuist_cache")
	if err := os.MkdirAll(workspace, 0755); err != nil {
		t.Fatal(err)
	}
	t.Chdir(workspace)
	scope := digest("scope")
	source := filepath.Join(cache, scope, digest(".gradle/caches/modules-2"))
	if err := os.MkdirAll(source, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(source, "dependency"), []byte("retained"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cache, scope, ".tuist-volume"), []byte("lease-id"), 0644); err != nil {
		t.Fatal(err)
	}
	broker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "" {
			t.Error("workflow credential leaked")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"directory":"` + scope + `","warm":true,"id":"lease-id"}`))
	}))
	defer broker.Close()
	t.Setenv("TUIST_CACHE_VOLUME_URL", broker.URL)
	if err := attachWithMounter("gradle", []string{".gradle/caches/modules-2", ".gradle/wrapper"}, cache, broker.Client(), func(socket, source, target string) error {
		return os.Symlink(filepath.Join(cache, source), target+"/mounted")
	}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(".gradle/caches/modules-2/mounted/dependency")
	if err != nil || string(data) != "retained" {
		t.Fatalf("cache not visible: %s %v", data, err)
	}
	if err := os.WriteFile(".gradle/caches/modules-2/mounted/new", []byte("new"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(source, "new")); err != nil {
		t.Fatal("writes do not reach volume")
	}
}
func TestRejectOverlappingTargetsBeforeAttaching(t *testing.T) {
	root := t.TempDir()
	cache := filepath.Join(root, "cache")
	a := filepath.Join(root, "workspace/a")
	if err := attachWithClient("key", []string{a, filepath.Join(a, "child")}, cache, nil); err == nil {
		t.Fatal("accepted overlapping paths")
	}
	if err := attachWithClient("key", []string{cache}, cache, nil); err == nil {
		t.Fatal("accepted cache mount as target")
	}
}

func TestMissingMountProofFallsBackWithoutLinkingHostDirectory(t *testing.T) {
	root := t.TempDir()
	cache := filepath.Join(root, "cache")
	scope := digest("scope")
	if err := os.MkdirAll(filepath.Join(cache, scope), 0755); err != nil {
		t.Fatal(err)
	}
	broker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"directory":"` + scope + `","id":"lease-id","warm":true}`))
	}))
	defer broker.Close()
	t.Setenv("TUIST_CACHE_VOLUME_URL", broker.URL)
	output := filepath.Join(root, "output")
	os.WriteFile(output, nil, 0600)
	t.Setenv("GITHUB_OUTPUT", output)
	target := filepath.Join(root, "target")
	if err := attachWithClient("key", []string{target}, cache, broker.Client()); err != nil {
		t.Fatal(err)
	}
	info, err := os.Lstat(target)
	if err != nil || info.Mode()&os.ModeSymlink != 0 {
		t.Fatal("linked unmounted directory", err)
	}
	data, _ := os.ReadFile(output)
	if string(data) != "cache-hit=false\n" {
		t.Fatalf("incorrect fallback output: %s", data)
	}
}

func TestRejectInvalidPathsBeforeAcquiringStorage(t *testing.T) {
	for _, path := range []string{"", "cache\n", "cache\r", "cache\t", "cache\x00", "cache\x1f", "cache\x7f"} {
		t.Run(path, func(t *testing.T) {
			err := attachWithClient("key", []string{filepath.Join(t.TempDir(), "valid"), path}, t.TempDir(), nil)
			if !errors.Is(err, errInvalidPath) {
				t.Fatalf("expected invalid path before HTTP request, got %v", err)
			}
		})
	}
}
