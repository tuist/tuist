package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
)

// Each job runs in its own builds directory, as it would on its own machine,
// so a restored archive can only have come through the remote cache.
func TestCacheCrossesMachines(t *testing.T) {
	dir := t.TempDir()
	repo, sha := fixtureRepository(t, dir)

	var mu sync.Mutex
	objects := map[string][]byte{}
	logs := map[string]*strings.Builder{}
	var objectNames []string

	var server *httptest.Server
	server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		switch {
		case r.URL.Path == "/reports/cache":
			if r.Header.Get("Authorization") != "Bearer report-secret" {
				t.Error("wrong cache credential")
			}
			var body struct {
				ObjectName string `json:"object_name"`
				ExpiresIn  int    `json:"expires_in"`
			}
			_ = json.NewDecoder(r.Body).Decode(&body)
			if body.ExpiresIn <= 0 {
				t.Errorf("missing expiry: %d", body.ExpiresIn)
			}
			objectNames = append(objectNames, body.ObjectName)
			url := server.URL + "/storage/" + body.ObjectName + "?X-Amz-Signature=presigned-secret"
			_ = json.NewEncoder(w).Encode(map[string]string{"download_url": url, "upload_url": url})
		case strings.HasPrefix(r.URL.Path, "/storage/"):
			if r.URL.Query().Get("X-Amz-Signature") != "presigned-secret" {
				t.Error("storage request lost its signature")
			}
			name := strings.TrimPrefix(r.URL.Path, "/storage/")
			switch r.Method {
			case http.MethodPut:
				objects[name], _ = io.ReadAll(r.Body)
				w.WriteHeader(200)
			case http.MethodGet:
				data, ok := objects[name]
				if !ok {
					w.WriteHeader(404)
					return
				}
				_, _ = w.Write(data)
			default:
				w.WriteHeader(405)
			}
		case strings.HasSuffix(r.URL.Path, "/trace"):
			id := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/api/v4/jobs/"), "/trace")
			if logs[id] == nil {
				logs[id] = &strings.Builder{}
			}
			_, _ = io.Copy(logs[id], r.Body)
			w.WriteHeader(202)
		case strings.HasPrefix(r.URL.Path, "/api/v4/jobs/") && r.Method == http.MethodPut:
			w.WriteHeader(200)
		case r.URL.Path == "/reports/finish" || r.URL.Path == "/reports/logs":
			_, _ = io.Copy(io.Discard, r.Body)
			w.WriteHeader(204)
		default:
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(404)
		}
	}))
	defer server.Close()

	run := func(id int, script string) {
		t.Helper()
		data, _ := json.Marshal(map[string]any{
			"url": server.URL, "report_url": server.URL + "/reports", "report_token": "report-secret",
			"payload": map[string]any{
				"id": id, "token": "job-secret", "runner_info": map[string]any{"timeout": 60},
				"job_info":  map[string]any{"name": "test", "project_id": 123, "project_name": "demo", "project_full_path": "acme/demo"},
				"git_info":  map[string]any{"repo_url": repo, "ref": "main", "sha": sha, "ref_type": "branch", "refspecs": []string{"+refs/heads/*:refs/remotes/origin/*"}},
				"variables": []map[string]any{{"key": "GIT_STRATEGY", "value": "clone"}},
				"steps":     []map[string]any{{"name": "script", "script": []string{script}, "timeout": 60, "when": "on_success"}},
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

	run(1, "mkdir -p vendor && echo warm-from-first-machine > vendor/cached.txt")
	run(2, "cat vendor/cached.txt")

	mu.Lock()
	defer mu.Unlock()
	if _, ok := objects["project/123/deps"]; !ok {
		t.Fatalf("no archive uploaded; stored: %v", keys(objects))
	}
	for _, name := range objectNames {
		if name != "project/123/deps" {
			t.Errorf("unexpected object name %q", name)
		}
	}
	second := logs["2"]
	if second == nil || !strings.Contains(second.String(), "warm-from-first-machine") {
		t.Fatalf("second machine did not restore the cache:\n%v", second)
	}
	for id, log := range logs {
		if strings.Contains(log.String(), "presigned-secret") {
			t.Errorf("job %s log exposes a cache URL signature", id)
		}
	}
}

func TestCacheUnavailableKeepsJobRunning(t *testing.T) {
	dir := t.TempDir()
	repo, sha := fixtureRepository(t, dir)
	var mu sync.Mutex
	var outcome map[string]any
	cacheRequests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		switch {
		case r.URL.Path == "/reports/cache":
			cacheRequests++
			w.WriteHeader(404)
		case r.URL.Path == "/reports/finish":
			_ = json.NewDecoder(r.Body).Decode(&outcome)
			w.WriteHeader(204)
		case strings.HasPrefix(r.URL.Path, "/api/v4/jobs/") || r.URL.Path == "/reports/logs":
			_, _ = io.Copy(io.Discard, r.Body)
			if strings.HasSuffix(r.URL.Path, "/trace") {
				w.WriteHeader(202)
				return
			}
			w.WriteHeader(200)
		default:
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(404)
		}
	}))
	defer server.Close()
	data, _ := json.Marshal(map[string]any{
		"url": server.URL, "report_url": server.URL + "/reports", "report_token": "report-secret",
		"payload": map[string]any{
			"id": 7, "token": "job-secret", "runner_info": map[string]any{"timeout": 60},
			"job_info":  map[string]any{"name": "test", "project_id": 123},
			"git_info":  map[string]any{"repo_url": repo, "ref": "main", "sha": sha, "ref_type": "branch", "refspecs": []string{"+refs/heads/*:refs/remotes/origin/*"}},
			"variables": []map[string]any{{"key": "GIT_STRATEGY", "value": "clone"}},
			"steps":     []map[string]any{{"name": "script", "script": []string{"mkdir -p vendor && echo ok > vendor/x"}, "timeout": 60, "when": "on_success"}},
			"cache":     []map[string]any{{"key": "deps", "paths": []string{"vendor"}, "policy": "pull-push", "when": "on_success"}},
		},
	})
	jobFile := filepath.Join(dir, "job.json")
	if err := os.WriteFile(jobFile, data, 0600); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command(os.Args[0], "--job-file", jobFile, "--builds-dir", filepath.Join(dir, "builds")).CombinedOutput(); err != nil {
		t.Fatalf("runner failed: %v\n%s", err, output)
	}
	mu.Lock()
	defer mu.Unlock()
	if cacheRequests == 0 {
		t.Fatal("executor never asked for cache URLs")
	}
	if outcome == nil || outcome["exit_status"] != float64(0) {
		t.Fatalf("job must succeed without a remote cache: %v", outcome)
	}
}

func keys(m map[string][]byte) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
