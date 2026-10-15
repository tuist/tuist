package payload

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type entry struct {
	name     string
	body     string
	mode     int64
	typeflag byte
	linkname string
}

func archive(t *testing.T, entries ...entry) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for _, e := range entries {
		typeflag := e.typeflag
		if typeflag == 0 {
			typeflag = tar.TypeReg
		}
		mode := e.mode
		if mode == 0 {
			mode = 0o644
		}
		hdr := &tar.Header{Name: e.name, Mode: mode, Size: int64(len(e.body)), Typeflag: typeflag, Linkname: e.linkname}
		if typeflag != tar.TypeReg {
			hdr.Size = 0
		}
		if err := tw.WriteHeader(hdr); err != nil {
			t.Fatal(err)
		}
		if typeflag == tar.TypeReg {
			if _, err := tw.Write([]byte(e.body)); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func digest(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

type registry struct {
	server       *httptest.Server
	manifest     []byte
	layer        []byte
	requireToken bool
	requests     atomic.Int32
}

func newRegistry(t *testing.T, layer []byte, mediaType string) *registry {
	t.Helper()
	r := &registry{layer: layer, requireToken: true}
	m := map[string]any{
		"schemaVersion": 2,
		"mediaType":     manifestMediaType,
		"layers": []map[string]any{{
			"mediaType": mediaType,
			"digest":    "sha256:" + digest(layer),
			"size":      len(layer),
		}},
	}
	raw, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	r.manifest = raw
	r.server = httptest.NewServer(http.HandlerFunc(r.serve))
	t.Cleanup(r.server.Close)
	return r
}

func (r *registry) serve(w http.ResponseWriter, req *http.Request) {
	r.requests.Add(1)
	if req.URL.Path == "/token" {
		if req.URL.Query().Get("scope") != "repository:tuist/tuist-runner-payload:pull" {
			http.Error(w, "bad scope", http.StatusBadRequest)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]string{"token": "anonymous"})
		return
	}
	if r.requireToken && req.Header.Get("Authorization") != "Bearer anonymous" {
		w.Header().Set("WWW-Authenticate", fmt.Sprintf(`Bearer realm="%s/token",service="registry"`, r.server.URL))
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	switch req.URL.Path {
	case "/v2/tuist/tuist-runner-payload/manifests/sha256:" + digest(r.manifest):
		_, _ = w.Write(r.manifest)
	case "/v2/tuist/tuist-runner-payload/blobs/sha256:" + digest(r.layer):
		_, _ = w.Write(r.layer)
	default:
		http.NotFound(w, req)
	}
}

func (r *registry) ref() string {
	return strings.TrimPrefix(r.server.URL, "http://") + "/tuist/tuist-runner-payload@sha256:" + digest(r.manifest)
}

func fetcher(t *testing.T) *Fetcher {
	t.Helper()
	return &Fetcher{Root: filepath.Join(t.TempDir(), "payloads"), Scheme: "http"}
}

func TestEnsureUnpacksVerifiedPayload(t *testing.T) {
	reg := newRegistry(t, archive(t,
		entry{name: "opt/tuist/", typeflag: tar.TypeDir},
		entry{name: "opt/tuist/dispatch-poll.sh", body: "#!/bin/bash\n", mode: 0o755},
		entry{name: "VERSION", body: "1.2.3\n"},
	), LayerMediaType)
	f := fetcher(t)

	dir, err := f.Ensure(context.Background(), reg.ref())
	if err != nil {
		t.Fatal(err)
	}

	script, err := os.Stat(filepath.Join(dir, "opt/tuist/dispatch-poll.sh"))
	if err != nil {
		t.Fatal(err)
	}
	if script.Mode().Perm() != 0o755 {
		t.Fatalf("script mode = %v, want 0755", script.Mode().Perm())
	}
	version, err := os.ReadFile(filepath.Join(dir, "VERSION"))
	if err != nil || string(version) != "1.2.3\n" {
		t.Fatalf("VERSION = %q, %v", version, err)
	}
	info, err := os.Stat(dir)
	if err != nil || info.Mode().Perm() != 0o755 {
		t.Fatalf("payload dir mode = %v, %v", info.Mode().Perm(), err)
	}
}

func TestEnsureReusesCachedPayload(t *testing.T) {
	reg := newRegistry(t, archive(t, entry{name: "VERSION", body: "1"}), LayerMediaType)
	f := fetcher(t)
	first, err := f.Ensure(context.Background(), reg.ref())
	if err != nil {
		t.Fatal(err)
	}
	before := reg.requests.Load()

	second, err := f.Ensure(context.Background(), reg.ref())
	if err != nil {
		t.Fatal(err)
	}

	if first != second {
		t.Fatalf("second Ensure returned %q, want %q", second, first)
	}
	if reg.requests.Load() != before {
		t.Fatal("cached payload was fetched again")
	}
}

func TestEnsureRejectsTagReferences(t *testing.T) {
	f := fetcher(t)
	if _, err := f.Ensure(context.Background(), "ghcr.io/tuist/tuist-runner-payload:1.0.0"); err == nil {
		t.Fatal("tag reference accepted")
	}
}

func TestEnsureRejectsTamperedLayer(t *testing.T) {
	reg := newRegistry(t, archive(t, entry{name: "VERSION", body: "1"}), LayerMediaType)
	reg.layer = archive(t, entry{name: "VERSION", body: "2"})
	f := fetcher(t)

	if _, err := f.Ensure(context.Background(), reg.ref()); err == nil {
		t.Fatal("tampered layer accepted")
	}
	assertNoPayloads(t, f)
}

func TestEnsureRejectsUnexpectedMediaType(t *testing.T) {
	reg := newRegistry(t, archive(t, entry{name: "VERSION", body: "1"}), "application/vnd.oci.image.layer.v1.tar+gzip")
	f := fetcher(t)

	if _, err := f.Ensure(context.Background(), reg.ref()); err == nil {
		t.Fatal("foreign layer media type accepted")
	}
}

func TestEnsureRejectsUnsafeEntries(t *testing.T) {
	for name, e := range map[string]entry{
		"traversal": {name: "../escape", body: "x"},
		"absolute":  {name: "/etc/passwd", body: "x"},
		"symlink":   {name: "opt/tuist/link", typeflag: tar.TypeSymlink, linkname: "/etc/passwd"},
		"hardlink":  {name: "opt/tuist/link", typeflag: tar.TypeLink, linkname: "VERSION"},
	} {
		t.Run(name, func(t *testing.T) {
			reg := newRegistry(t, archive(t, e), LayerMediaType)
			f := fetcher(t)

			if _, err := f.Ensure(context.Background(), reg.ref()); err == nil {
				t.Fatal("unsafe entry accepted")
			}
			assertNoPayloads(t, f)
		})
	}
}

func TestEnsureFetchesWithoutAuthChallenge(t *testing.T) {
	reg := newRegistry(t, archive(t, entry{name: "VERSION", body: "1"}), LayerMediaType)
	reg.requireToken = false
	f := fetcher(t)

	if _, err := f.Ensure(context.Background(), reg.ref()); err != nil {
		t.Fatal(err)
	}
}

func TestEnsureKeepsOnlyRecentPayloads(t *testing.T) {
	f := fetcher(t)
	var dirs []string
	for i := range 4 {
		reg := newRegistry(t, archive(t, entry{name: "VERSION", body: fmt.Sprint(i)}), LayerMediaType)
		dir, err := f.Ensure(context.Background(), reg.ref())
		if err != nil {
			t.Fatal(err)
		}
		past := time.Now().Add(time.Duration(i-10) * time.Minute)
		if err := os.Chtimes(dir, past, past); err != nil {
			t.Fatal(err)
		}
		dirs = append(dirs, dir)
	}

	if _, err := os.Stat(dirs[0]); !os.IsNotExist(err) {
		t.Fatalf("oldest payload still cached: %v", err)
	}
	for _, dir := range dirs[1:] {
		if _, err := os.Stat(dir); err != nil {
			t.Fatalf("recent payload %s pruned: %v", dir, err)
		}
	}
}

func assertNoPayloads(t *testing.T, f *Fetcher) {
	t.Helper()
	entries, err := os.ReadDir(f.Root)
	if err != nil {
		if os.IsNotExist(err) {
			return
		}
		t.Fatal(err)
	}
	for _, e := range entries {
		t.Errorf("left %s behind", e.Name())
	}
}
