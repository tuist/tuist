package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"testing"
)

// fakeCache serves the Tuist cache endpoints and the object storage they
// presign, assembling multipart uploads the way object storage does. Other
// requests, such as GitLab's, go to coordinator.
type fakeCache struct {
	t           *testing.T
	server      *httptest.Server
	coordinator http.HandlerFunc
	mu          sync.Mutex
	objects     map[string][]byte
	uploads     map[string]map[int][]byte
	completed   map[string][]cachePart
	aborted     []string
	requests    map[string]int
	nextID      int
	failPart    int // Every PUT of this part number fails.
	failures    int // The next N part PUTs fail before one succeeds.
	refuse      bool
}

func newFakeCache(t *testing.T) *fakeCache {
	f := &fakeCache{
		t: t, objects: map[string][]byte{}, uploads: map[string]map[int][]byte{},
		completed: map[string][]cachePart{}, requests: map[string]int{},
	}
	f.server = httptest.NewServer(http.HandlerFunc(f.serve))
	t.Cleanup(f.server.Close)
	return f
}

func (f *fakeCache) client() *cacheClient {
	return newCacheClient(f.server.URL+"/reports", "report-secret")
}

func (f *fakeCache) serve(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if strings.HasPrefix(r.URL.Path, "/reports/cache/") {
		f.requests[strings.TrimPrefix(r.URL.Path, "/reports/cache/")]++
		if r.Header.Get("Authorization") != "Bearer report-secret" {
			f.t.Error("wrong cache credential")
		}
		if f.refuse {
			w.WriteHeader(404)
			return
		}
	}
	var body struct {
		ObjectName string      `json:"object_name"`
		UploadID   string      `json:"upload_id"`
		PartNumber int         `json:"part_number"`
		Parts      []cachePart `json:"parts"`
	}
	if strings.HasPrefix(r.URL.Path, "/reports/cache/") {
		_ = json.NewDecoder(r.Body).Decode(&body)
	}
	signature := "?X-Amz-Signature=presigned-secret"
	switch {
	case r.URL.Path == "/reports/cache/download":
		_ = json.NewEncoder(w).Encode(map[string]string{"url": f.server.URL + "/storage/" + body.ObjectName + signature})
	case r.URL.Path == "/reports/cache/uploads":
		f.nextID++
		id := strconv.Itoa(f.nextID)
		f.uploads[id] = map[int][]byte{}
		_ = json.NewEncoder(w).Encode(map[string]string{"upload_id": id})
	case r.URL.Path == "/reports/cache/uploads/part":
		url := fmt.Sprintf("%s/parts/%s/%d%s", f.server.URL, body.UploadID, body.PartNumber, signature)
		_ = json.NewEncoder(w).Encode(map[string]string{"url": url})
	case r.URL.Path == "/reports/cache/uploads/complete":
		var object []byte
		for i, part := range body.Parts {
			if part.PartNumber != i+1 || part.ETag != fmt.Sprintf("etag-%d", part.PartNumber) {
				f.t.Errorf("unexpected part %+v at position %d", part, i)
			}
			object = append(object, f.uploads[body.UploadID][part.PartNumber]...)
		}
		f.objects[body.ObjectName] = object
		f.completed[body.ObjectName] = body.Parts
		w.WriteHeader(204)
	case r.URL.Path == "/reports/cache/uploads/abort":
		f.aborted = append(f.aborted, body.UploadID)
		w.WriteHeader(204)
	case strings.HasPrefix(r.URL.Path, "/parts/") && r.Method == http.MethodPut:
		if r.URL.Query().Get("X-Amz-Signature") != "presigned-secret" {
			f.t.Error("part upload lost its signature")
		}
		segments := strings.Split(strings.TrimPrefix(r.URL.Path, "/parts/"), "/")
		number, _ := strconv.Atoi(segments[1])
		data, _ := io.ReadAll(r.Body)
		if int64(len(data)) != r.ContentLength {
			f.t.Errorf("part %d sent %d bytes with Content-Length %d", number, len(data), r.ContentLength)
		}
		if number == f.failPart || f.failures > 0 {
			f.failures--
			w.WriteHeader(500)
			return
		}
		f.uploads[segments[0]][number] = data
		w.Header().Set("ETag", fmt.Sprintf("etag-%d", number))
		w.WriteHeader(200)
	case strings.HasPrefix(r.URL.Path, "/storage/") && r.Method == http.MethodGet:
		data, ok := f.objects[strings.TrimPrefix(r.URL.Path, "/storage/")]
		if !ok {
			w.WriteHeader(404)
			return
		}
		_, _ = w.Write(data)
	case f.coordinator != nil:
		f.coordinator(w, r)
	default:
		f.t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
		w.WriteHeader(404)
	}
}

func TestCacheWriterUploadsInParts(t *testing.T) {
	f := newFakeCache(t)
	data := bytes.Repeat([]byte("0123456789"), 25)
	w := &cacheWriter{ctx: context.Background(), client: f.client(), objectName: "project/1/deps", partSize: 100}

	// Irregular writes must not move where parts break.
	for _, chunk := range [][]byte{data[:7], data[7:180], data[180:]} {
		if _, err := w.Write(chunk); err != nil {
			t.Fatal(err)
		}
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}

	if !bytes.Equal(f.objects["project/1/deps"], data) {
		t.Fatalf("assembled object differs: %d bytes", len(f.objects["project/1/deps"]))
	}
	if n := len(f.completed["project/1/deps"]); n != 3 {
		t.Fatalf("expected 3 parts, got %d", n)
	}
	if f.requests["uploads"] != 1 || len(f.aborted) != 0 {
		t.Fatalf("starts=%d aborted=%v", f.requests["uploads"], f.aborted)
	}
}

func TestCacheWriterUploadsEmptyArchiveAsOnePart(t *testing.T) {
	f := newFakeCache(t)
	w := &cacheWriter{ctx: context.Background(), client: f.client(), objectName: "project/1/empty", partSize: 100}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	if parts, ok := f.completed["project/1/empty"]; !ok || len(parts) != 1 {
		t.Fatalf("expected one completed part, got %v", parts)
	}
}

func TestCacheWriterRetriesTransientPartFailures(t *testing.T) {
	f := newFakeCache(t)
	f.failures = 1
	w := &cacheWriter{ctx: context.Background(), client: f.client(), objectName: "project/1/deps", partSize: 100}
	if _, err := w.Write([]byte("retry me")); err != nil {
		t.Fatal(err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	if string(f.objects["project/1/deps"]) != "retry me" {
		t.Fatalf("object: %q", f.objects["project/1/deps"])
	}
}

func TestCacheWriterAbortsFailedUpload(t *testing.T) {
	f := newFakeCache(t)
	f.failPart = 2
	w := &cacheWriter{ctx: context.Background(), client: f.client(), objectName: "project/1/deps", partSize: 100}

	_, err := w.Write(make([]byte, 250))
	if err == nil {
		t.Fatal("write must fail once a part keeps failing")
	}
	if _, again := w.Write([]byte("more")); !errors.Is(again, err) {
		t.Fatalf("writes after a failure must keep failing, got %v", again)
	}
	if w.Close() == nil {
		t.Fatal("close must report the failure")
	}
	if len(f.aborted) != 1 || f.requests["uploads/complete"] != 0 {
		t.Fatalf("aborted=%v completes=%d", f.aborted, f.requests["uploads/complete"])
	}
}

func TestCacheWriterAbortsWhenCancelled(t *testing.T) {
	f := newFakeCache(t)
	ctx, cancel := context.WithCancel(context.Background())
	w := &cacheWriter{ctx: ctx, client: f.client(), objectName: "project/1/deps", partSize: 100}
	if _, err := w.Write(make([]byte, 150)); err != nil {
		t.Fatal(err)
	}
	cancel()
	if err := w.Close(); !errors.Is(err, context.Canceled) {
		t.Fatalf("close after cancellation: %v", err)
	}
	if len(f.aborted) != 1 || f.requests["uploads/complete"] != 0 {
		t.Fatalf("aborted=%v completes=%d", f.aborted, f.requests["uploads/complete"])
	}
}

// Each job runs in its own builds directory, as it would on its own machine,
// so a restored archive can only have come through the remote cache. The
// archive is larger than a part, so it crosses as a multipart upload.
func TestCacheCrossesMachines(t *testing.T) {
	dir := t.TempDir()
	repo, sha := fixtureRepository(t, dir)
	f := newFakeCache(t)
	logs := map[int]*strings.Builder{}
	f.coordinator = func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/trace"):
			id, _ := strconv.Atoi(strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/api/v4/jobs/"), "/trace"))
			if logs[id] == nil {
				logs[id] = &strings.Builder{}
			}
			_, _ = io.Copy(logs[id], r.Body)
			w.WriteHeader(202)
		default:
			_, _ = io.Copy(io.Discard, r.Body)
			w.WriteHeader(200)
		}
	}

	checksum := `echo "checksum=$(cksum vendor/large.bin | cut -d ' ' -f 1,2)"`
	runCacheJob(t, dir, 1, f.server.URL, repo, sha, "mkdir -p vendor && head -c 70000000 /dev/urandom > vendor/large.bin && "+checksum)
	runCacheJob(t, dir, 2, f.server.URL, repo, sha, checksum)

	f.mu.Lock()
	defer f.mu.Unlock()
	if parts := len(f.completed["project/123/deps"]); parts < 2 {
		t.Fatalf("expected a multipart upload, got %d parts", parts)
	}
	pattern := regexp.MustCompile(`checksum=(\d+ \d+)`)
	first, second := pattern.FindStringSubmatch(logs[1].String()), pattern.FindStringSubmatch(logs[2].String())
	if first == nil || second == nil || first[1] != second[1] {
		t.Fatalf("second machine did not restore the archive: first=%v second=%v\n%s", first, second, logs[2])
	}
	for id, log := range logs {
		for _, secret := range []string{"presigned-secret", "report-secret"} {
			if strings.Contains(log.String(), secret) {
				t.Errorf("job %d log exposes %s", id, secret)
			}
		}
	}
}

func TestCacheUnavailableKeepsJobRunning(t *testing.T) {
	dir := t.TempDir()
	repo, sha := fixtureRepository(t, dir)
	f := newFakeCache(t)
	f.refuse = true
	var outcome map[string]any
	f.coordinator = func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/reports/finish" {
			_ = json.NewDecoder(r.Body).Decode(&outcome)
			w.WriteHeader(204)
			return
		}
		_, _ = io.Copy(io.Discard, r.Body)
		if strings.HasSuffix(r.URL.Path, "/trace") {
			w.WriteHeader(202)
			return
		}
		w.WriteHeader(200)
	}

	runCacheJob(t, dir, 7, f.server.URL, repo, sha, "mkdir -p vendor && echo ok > vendor/x")

	f.mu.Lock()
	defer f.mu.Unlock()
	if f.requests["download"] == 0 || f.requests["uploads"] == 0 {
		t.Fatalf("executor never asked for cache storage: %v", f.requests)
	}
	if outcome == nil || outcome["exit_status"] != float64(0) {
		t.Fatalf("job must succeed without a remote cache: %v", outcome)
	}
}

func runCacheJob(t *testing.T, dir string, id int, serverURL, repo, sha, script string) {
	t.Helper()
	data, _ := json.Marshal(map[string]any{
		"url": serverURL, "report_url": serverURL + "/reports", "report_token": "report-secret",
		"payload": map[string]any{
			"id": id, "token": "job-secret", "runner_info": map[string]any{"timeout": 300},
			"job_info":  map[string]any{"name": "test", "project_id": 123, "project_name": "demo", "project_full_path": "acme/demo"},
			"git_info":  map[string]any{"repo_url": repo, "ref": "main", "sha": sha, "ref_type": "branch", "refspecs": []string{"+refs/heads/*:refs/remotes/origin/*"}},
			"variables": []map[string]any{{"key": "GIT_STRATEGY", "value": "clone"}},
			"steps":     []map[string]any{{"name": "script", "script": []string{script}, "timeout": 300, "when": "on_success"}},
			"cache":     []map[string]any{{"key": "deps", "paths": []string{"vendor"}, "policy": "pull-push", "when": "on_success"}},
		},
	})
	machine := filepath.Join(dir, "machine", strconv.Itoa(id))
	jobFile := filepath.Join(machine, "job.json")
	if err := os.MkdirAll(machine, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(jobFile, data, 0600); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command(os.Args[0], "--job-file", jobFile, "--builds-dir", filepath.Join(machine, "builds")).CombinedOutput(); err != nil {
		t.Fatalf("runner failed: %v\n%s", err, output)
	}
}
