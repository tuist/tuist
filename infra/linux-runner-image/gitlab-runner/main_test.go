package main

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
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
		infraFailure bool
	}{
		{"success with checkout artifacts and masked logs", "0", false, false, false},
		{"executor cannot start shell", "0", false, false, true},
		{"script failure", "7", false, false, false},
		{"cancel before execution", "0", true, false, false},
		{"cancel while running", "7", false, true, false},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			dir := t.TempDir()
			repo, sha := fixtureRepository(t, dir)
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
			jobFile := filepath.Join(dir, "job.json")
			if err := os.WriteFile(jobFile, data, 0600); err != nil {
				t.Fatal(err)
			}
			buildsDir := filepath.Join(dir, "builds")
			resultFile := filepath.Join(dir, "job-result")
			cmd := exec.Command(os.Args[0], "--job-file", jobFile, "--builds-dir", buildsDir, "--result-file", resultFile)
			if scenario.infraFailure {
				cmd.Env = append(os.Environ(), "PATH="+dir)
			}
			output, err := cmd.CombinedOutput()
			mu.Lock()
			defer mu.Unlock()
			if scenario.infraFailure && err == nil {
				t.Fatal("infrastructure failure must exit the runner non-zero")
			}
			if !scenario.infraFailure && err != nil {
				t.Fatalf("job outcome must exit the runner zero: %v\n%s", err, output)
			}
			if outcome == nil {
				t.Fatal("no completion report")
			}
			result, _ := os.ReadFile(resultFile)
			wantResult := "failed"
			switch {
			case scenario.infraFailure:
			case scenario.cancel || scenario.activeCancel:
				wantResult = "canceled"
			case scenario.exit == "0":
				wantResult = "succeeded"
			}
			if string(result) != wantResult {
				t.Errorf("result file = %q, want %q", result, wantResult)
			}
			if scenario.infraFailure {
				if outcome["exit_status"] == float64(0) || states[len(states)-1] != "failed" {
					t.Fatalf("lost infrastructure failure: outcome=%v states=%v", outcome, states)
				}
				return
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
				if outcome["exit_status"] != float64(7) {
					t.Errorf("lost script failure: %v", outcome)
				}
				if states[len(states)-1] != "failed" {
					t.Errorf("states: %v", states)
				}
			}
		})
	}
}

func fixtureRepository(t *testing.T, dir string) (string, string) {
	t.Helper()
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
	return repo, git("rev-parse", "HEAD")
}

func TestExecuteContinuesAfterServerWaitingTrace(t *testing.T) {
	for _, serverWrote := range []bool{true, false} {
		t.Run(fmt.Sprintf("server wrote waiting trace: %v", serverWrote), func(t *testing.T) {
			dir := t.TempDir()
			repo, sha := fixtureRepository(t, dir)
			waitingTrace := "2026-09-23T10:00:00.000000Z 00O section_start:1790157600:" + waitingSection + "\r\x1b[0KWaiting for a Tuist runner for tuist-macos (4 vCPU, 16 GB)\n"
			var mu sync.Mutex
			var stored, tuistLog strings.Builder
			if serverWrote {
				stored.WriteString(waitingTrace)
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				mu.Lock()
				defer mu.Unlock()
				switch {
				case r.URL.Path == "/api/v4/jobs/42/trace":
					// Like GitLab, accept only a patch that starts where the stored log ends.
					var start, end int
					if _, err := fmt.Sscanf(r.Header.Get("Content-Range"), "%d-%d", &start, &end); err != nil || start != stored.Len() {
						w.Header().Set("Range", fmt.Sprintf("0-%d", stored.Len()))
						w.WriteHeader(http.StatusRequestedRangeNotSatisfiable)
						return
					}
					_, _ = io.Copy(&stored, r.Body)
					w.WriteHeader(202)
				case r.URL.Path == "/api/v4/jobs/42" && r.Method == "PUT":
					w.WriteHeader(200)
				case r.URL.Path == "/reports/logs":
					var body struct {
						Lines []string `json:"lines"`
					}
					_ = json.NewDecoder(r.Body).Decode(&body)
					tuistLog.WriteString(strings.Join(body.Lines, "\n"))
					w.WriteHeader(204)
				default:
					w.WriteHeader(204)
				}
			}))
			defer server.Close()
			data, _ := json.Marshal(map[string]any{
				"url": server.URL, "report_url": server.URL + "/reports", "report_token": "report-secret",
				"waiting_trace": waitingTrace,
				"payload": map[string]any{
					"id": 42, "token": "job-secret", "runner_info": map[string]any{"timeout": 60},
					"job_info":  map[string]any{"name": "test", "project_id": 123, "project_name": "demo", "project_full_path": "acme/demo"},
					"git_info":  map[string]any{"repo_url": repo, "ref": "main", "sha": sha, "ref_type": "branch", "refspecs": []string{"+refs/heads/*:refs/remotes/origin/*"}},
					"variables": []map[string]any{{"key": "GIT_STRATEGY", "value": "clone"}},
					"steps":     []map[string]any{{"name": "script", "script": []string{"cat source.txt"}, "timeout": 60, "when": "on_success"}},
				},
			})
			jobFile := filepath.Join(dir, "job.json")
			if err := os.WriteFile(jobFile, data, 0600); err != nil {
				t.Fatal(err)
			}
			cmd := exec.Command(os.Args[0], "--job-file", jobFile, "--builds-dir", filepath.Join(dir, "builds"))
			if output, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("%v\n%s", err, output)
			}
			mu.Lock()
			defer mu.Unlock()
			log := stored.String()
			lines := strings.Split(strings.TrimSuffix(log, "\n"), "\n")
			if len(lines) < 3 || lines[0]+"\n" != waitingTrace || !strings.Contains(lines[1], "00O section_end:") {
				t.Fatalf("log does not continue the waiting section: %q", log[:min(len(log), 300)])
			}
			// GitLab takes the first line's timestamp header to mean every line has one.
			for _, line := range lines {
				if !timestampHeader.MatchString(line) {
					t.Fatalf("line without a timestamp header: %q", line)
				}
			}
			if strings.Count(log, "Waiting for a Tuist runner") != 1 || !strings.Contains(log, "Running with gitlab-runner") || !strings.Contains(log, "checkout worked") {
				t.Fatalf("log lost or repeated output: %q", log)
			}
			if !strings.Contains(tuistLog.String(), "Waiting for a Tuist runner for tuist-macos") {
				t.Fatalf("Tuist log misses the waiting section: %q", tuistLog.String())
			}
		})
	}
}

func TestWriteWaitingTraceClosesTheSection(t *testing.T) {
	now := time.Unix(1790000100, 0)
	for _, tc := range []struct{ waitingTrace, want string }{
		{"", ""},
		{"opened\n", "opened\nsection_end:1790000100:tuist_waiting_for_runner\r\x1b[0K\n"},
		{
			"2026-09-23T10:00:00.000000Z 00O opened\n",
			"2026-09-23T10:00:00.000000Z 00O opened\n2026-09-21T14:15:00.000000Z 00O section_end:1790000100:tuist_waiting_for_runner\r\x1b[0K\n",
		},
	} {
		var buffer strings.Builder
		writeWaitingTrace(&buffer, tc.waitingTrace, now)
		if buffer.String() != tc.want {
			t.Errorf("got %q, want %q", buffer.String(), tc.want)
		}
	}
}
