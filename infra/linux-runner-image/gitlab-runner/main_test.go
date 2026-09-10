package main

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestMain(m *testing.M) {
	// GitLab's shell executor invokes its executable for artifact helpers.
	// In these integration tests that executable is the test binary.
	if len(os.Args) > 1 && !strings.HasPrefix(os.Args[1], "-test.") {
		main()
		return
	}
	os.Exit(m.Run())
}

func TestExecute(t *testing.T) {
	for _, scenario := range []struct {
		name         string
		exit         string
		cancel       bool
		activeCancel bool
	}{
		{"success with checkout artifacts and masked logs", "0", false, false},
		{"script failure", "7", false, false},
		{"cancel before execution", "0", true, false},
		{"cancel while running", "7", false, true},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			dir := t.TempDir()
			repo := filepath.Join(dir, "repository")
			if err := os.Mkdir(repo, 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(repo, "source.txt"), []byte("checkout worked\n"), 0600); err != nil {
				t.Fatal(err)
			}
			git := func(args ...string) string {
				cmd := exec.Command("git", args...)
				cmd.Dir = repo
				out, err := cmd.CombinedOutput()
				if err != nil {
					t.Fatalf("git: %v: %s", err, out)
				}
				return strings.TrimSpace(string(out))
			}
			git("init", "-b", "main")
			git("add", "source.txt")
			git("-c", "user.name=Local Test", "-c", "user.email=test@example.invalid", "commit", "-m", "fixture")
			sha := git("rev-parse", "HEAD")
			var mu sync.Mutex
			var upstreamLog, tuistLog strings.Builder
			var outcome map[string]any
			var states []string
			var uploaded bool
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				mu.Lock()
				defer mu.Unlock()
				switch {
				case r.URL.Path == "/api/v4/jobs/request":
					t.Error("executor tried to acquire another job")
					w.WriteHeader(403)
				case r.URL.Path == "/api/v4/jobs/42/trace":
					if r.Header.Get("JOB-TOKEN") != "job-secret" {
						t.Error("wrong trace credential")
					}
					_, _ = io.Copy(&upstreamLog, r.Body)
					if scenario.activeCancel && strings.Contains(upstreamLog.String(), "ready-to-cancel") {
						w.Header().Set("Job-Status", "canceling")
					}
					w.WriteHeader(202)
				case r.URL.Path == "/api/v4/jobs/42" && r.Method == "PUT":
					var body map[string]any
					_ = json.NewDecoder(r.Body).Decode(&body)
					if body["token"] != "job-secret" {
						t.Error("wrong status credential")
					}
					states = append(states, body["state"].(string))
					if scenario.cancel {
						w.Header().Set("Job-Status", "canceled")
					}
					w.WriteHeader(200)
				case r.URL.Path == "/api/v4/jobs/42/artifacts":
					if err := r.ParseMultipartForm(8 << 20); err != nil {
						t.Error(err)
						return
					}
					defer r.MultipartForm.RemoveAll()
					file, _, err := r.FormFile("file")
					if err != nil {
						t.Error(err)
						return
					}
					defer file.Close()
					data, _ := io.ReadAll(file)
					archive, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
					if err != nil {
						t.Error(err)
						return
					}
					for _, f := range archive.File {
						if f.Name == "artifact.txt" {
							uploaded = true
						}
					}
					w.WriteHeader(201)
				case r.URL.Path == "/reports/finish":
					if r.Header.Get("Authorization") != "Bearer report-secret" {
						t.Error("wrong report token")
					}
					_ = json.NewDecoder(r.Body).Decode(&outcome)
					w.WriteHeader(204)
				case r.URL.Path == "/reports/logs":
					var body struct {
						Lines []string `json:"lines"`
					}
					_ = json.NewDecoder(r.Body).Decode(&body)
					tuistLog.WriteString(strings.Join(body.Lines, "\n"))
					w.WriteHeader(204)
				default:
					t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
					w.WriteHeader(404)
				}
			}))
			defer server.Close()
			script := []string{"cat source.txt", "printf '%s\\n' \"$SECRET\"", "echo built > artifact.txt", "exit " + scenario.exit}
			if scenario.activeCancel {
				script = []string{"cat source.txt", "printf '%s\\n' \"$SECRET\"", "echo ready-to-cancel", "sleep 45"}
			}
			data, _ := json.Marshal(map[string]any{
				"url": server.URL, "report_url": server.URL + "/reports", "report_token": "report-secret",
				"payload": map[string]any{
					"id": 42, "token": "job-secret", "runner_info": map[string]any{"timeout": 60},
					"job_info": map[string]any{"name": "test", "project_id": 123, "project_name": "demo", "project_full_path": "acme/demo"},
					"git_info": map[string]any{"repo_url": repo, "ref": "main", "sha": sha, "ref_type": "branch", "refspecs": []string{"+refs/heads/*:refs/remotes/origin/*"}},
					"variables": []map[string]any{
						{"key": "SECRET", "value": "super-private-value", "masked": true},
						{"key": "GIT_STRATEGY", "value": "clone"},
					},
					"steps": []map[string]any{
						{"name": "script", "script": script, "timeout": 60, "when": "on_success"},
						{"name": "after_script", "script": []string{"echo after-script-ran"}, "timeout": 60, "when": "always"},
					},
					"artifacts": []map[string]any{{"paths": []string{"artifact.txt"}, "when": "on_success", "artifact_type": "archive", "artifact_format": "zip"}},
				},
			})
			var job assignment
			if err := json.Unmarshal(data, &job); err != nil {
				t.Fatal(err)
			}
			err := execute(job, filepath.Join(dir, "builds"))
			mu.Lock()
			defer mu.Unlock()
			if scenario.exit == "0" && !scenario.cancel && err != nil {
				t.Fatalf("execute: %v\n%s", err, tuistLog.String())
			}
			if (scenario.exit != "0" || scenario.cancel) && err == nil {
				t.Error("expected execution failure")
			}
			if outcome == nil {
				t.Fatal("no completion report")
			}
			if scenario.cancel || scenario.activeCancel {
				if outcome["cancelled"] != true {
					t.Fatalf("not cancelled: %v", outcome)
				}
				return
			}
			for _, log := range []string{tuistLog.String(), upstreamLog.String()} {
				if strings.Contains(log, "super-private-value") {
					t.Fatal("masked variable leaked")
				}
				if !strings.Contains(log, "[MASKED]") || !strings.Contains(log, "checkout worked") || !strings.Contains(log, "after-script-ran") {
					t.Fatalf("missing execution output: %s", log)
				}
			}
			if scenario.exit == "0" {
				if !uploaded {
					t.Error("artifact was not uploaded")
				}
				if outcome["exit_status"] != float64(0) {
					t.Errorf("outcome: %v", outcome)
				}
				if states[len(states)-1] != "success" {
					t.Errorf("states: %v", states)
				}
			} else {
				if outcome["exit_status"] == float64(0) {
					t.Errorf("lost script failure: %v", outcome)
				}
				if states[len(states)-1] != "failed" {
					t.Errorf("states: %v", states)
				}
			}
		})
	}
}
