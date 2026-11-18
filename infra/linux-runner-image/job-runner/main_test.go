package main

import (
	"context"
	"encoding/json"
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

// fakeServer records what the executor reports and answers log posts with
// cancel_requested once cancelAfter log posts have arrived (0 never cancels).
type fakeServer struct {
	mu          sync.Mutex
	lines       []string
	firsts      []int
	finish      map[string]any
	logPosts    int
	cancelAfter int
	tokens      []string
}

func (f *fakeServer) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		f.tokens = append(f.tokens, r.Header.Get("Authorization"))
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		switch r.URL.Path {
		case "/jobs/logs":
			f.logPosts++
			first := int(body["first_line_number"].(float64))
			f.firsts = append(f.firsts, first)
			for _, line := range body["lines"].([]any) {
				f.lines = append(f.lines, line.(string))
			}
			_ = json.NewEncoder(w).Encode(map[string]bool{"cancel_requested": f.cancelAfter > 0 && f.logPosts >= f.cancelAfter})
		case "/jobs/finish":
			f.finish = body
			w.WriteHeader(http.StatusNoContent)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	})
}

func (f *fakeServer) log() string {
	f.mu.Lock()
	defer f.mu.Unlock()
	var plain []string
	for _, line := range f.lines {
		_, text, _ := strings.Cut(line, "\x07")
		plain = append(plain, text)
	}
	return strings.Join(plain, "\n")
}

// repository creates a repository with two commits on main and returns its
// path with both commit SHAs, oldest first.
func repository(t *testing.T) (string, string, string) {
	t.Helper()
	dir := t.TempDir()
	git := func(args ...string) string {
		cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@example.com", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@example.com")
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	git("init", "--quiet", "--initial-branch=main")
	if err := os.WriteFile(filepath.Join(dir, "file.txt"), []byte("first\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	git("add", ".")
	git("commit", "--quiet", "-m", "first")
	first := git("rev-parse", "HEAD")
	if err := os.WriteFile(filepath.Join(dir, "file.txt"), []byte("second\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	git("commit", "--quiet", "-am", "second")
	return dir, first, git("rev-parse", "HEAD")
}

func runJob(t *testing.T, f *fakeServer, j job) (time.Duration, string) {
	t.Helper()
	server := httptest.NewServer(f.handler())
	defer server.Close()
	j.ReportURL = server.URL + "/jobs"
	j.ReportToken = "report-token"
	if j.WorkflowJobID == 0 {
		j.WorkflowJobID = 4000000000000001
	}
	builds := t.TempDir()
	result := filepath.Join(t.TempDir(), "result")
	started := time.Now()
	if err := run(context.Background(), j, config{buildsDir: builds, resultFile: result, flushInterval: 50 * time.Millisecond}); err != nil {
		t.Fatalf("run: %v", err)
	}
	content, _ := os.ReadFile(result)
	return time.Since(started), strings.TrimSpace(string(content))
}

func TestRunsTheScriptAtTheCommitAndMasksSecrets(t *testing.T) {
	repo, _, head := repository(t)
	f := &fakeServer{}
	_, result := runJob(t, f, job{
		Name:          "test",
		RepositoryURL: repo,
		CommitSHA:     head,
		Script:        "echo \"head=$(git rev-parse HEAD)\"\ncat file.txt\necho \"token=$API_TOKEN\"\necho \"plain=$PLAIN\"\necho \"sha=$TUIST_JOB_COMMIT_SHA\"\nprintf 'no newline'",
		Env:           map[string]string{"PLAIN": "visible"},
		Secrets:       map[string]string{"API_TOKEN": "s3cr3t-value"},
	})

	log := f.log()
	for _, want := range []string{"head=" + head, "second", "token=[MASKED]", "plain=visible", "sha=" + head, "no newline"} {
		if !strings.Contains(log, want) {
			t.Errorf("log is missing %q:\n%s", want, log)
		}
	}
	if strings.Contains(log, "s3cr3t-value") {
		t.Errorf("log leaks the secret:\n%s", log)
	}
	if f.finish["exit_status"] != float64(0) || f.finish["cancelled"] != false {
		t.Errorf("finish = %v", f.finish)
	}
	if result != "succeeded" {
		t.Errorf("result = %q", result)
	}
	for _, line := range f.lines {
		if !strings.HasPrefix(line, "\x1b_bk;t=") {
			t.Fatalf("line without a timestamp marker: %q", line)
		}
	}
	// Batches number their lines contiguously from 1.
	next := 1
	f.mu.Lock()
	for i, first := range f.firsts {
		if first != next {
			t.Errorf("batch %d starts at %d, want %d", i, first, next)
		}
		next = first
		next += countLinesInBatch(f, i)
	}
	f.mu.Unlock()
	for _, token := range f.tokens {
		if token != "Bearer report-token" {
			t.Errorf("authorization = %q", token)
		}
	}
}

// Batches are recorded in order, so a batch's size is the distance to the
// next batch's first line, or to the end for the last one.
func countLinesInBatch(f *fakeServer, i int) int {
	if i+1 < len(f.firsts) {
		return f.firsts[i+1] - f.firsts[i]
	}
	return len(f.lines) - f.firsts[i] + 1
}

func TestReportsTheScriptsExitStatus(t *testing.T) {
	repo, _, head := repository(t)
	f := &fakeServer{}
	_, result := runJob(t, f, job{RepositoryURL: repo, CommitSHA: head, Script: "echo before\nfalse\necho after"})

	if f.finish["exit_status"] != float64(1) || f.finish["cancelled"] != false {
		t.Errorf("finish = %v", f.finish)
	}
	if result != "failed" {
		t.Errorf("result = %q", result)
	}
	if log := f.log(); !strings.Contains(log, "before") || strings.Contains(log, "after") {
		t.Errorf("set -e did not stop the script:\n%s", log)
	}

	f = &fakeServer{}
	runJob(t, f, job{RepositoryURL: repo, CommitSHA: head, Script: "exit 7"})
	if f.finish["exit_status"] != float64(7) {
		t.Errorf("finish = %v", f.finish)
	}
}

func TestChecksOutACommitBehindTheRefTip(t *testing.T) {
	repo, first, _ := repository(t)
	f := &fakeServer{}
	runJob(t, f, job{RepositoryURL: "file://" + repo, Ref: "refs/heads/main", CommitSHA: first, Script: "git rev-parse HEAD; cat file.txt"})

	log := f.log()
	if !strings.Contains(log, first) || !strings.Contains(log, "first") {
		t.Errorf("did not check out the older commit:\n%s", log)
	}
	if f.finish["exit_status"] != float64(0) {
		t.Errorf("finish = %v", f.finish)
	}
}

func TestAMissingCommitFailsTheJob(t *testing.T) {
	repo, _, _ := repository(t)
	f := &fakeServer{}
	_, result := runJob(t, f, job{RepositoryURL: repo, CommitSHA: strings.Repeat("a", 40), Script: "echo never"})

	if f.finish["exit_status"] != float64(1) || result != "failed" {
		t.Errorf("finish = %v, result = %q", f.finish, result)
	}
	if log := f.log(); !strings.Contains(log, "Checkout failed") || strings.Contains(log, "never") {
		t.Errorf("log:\n%s", log)
	}
}

func TestStopsWhenTheServerAsksToCancel(t *testing.T) {
	repo, _, head := repository(t)
	f := &fakeServer{cancelAfter: 3}
	elapsed, result := runJob(t, f, job{RepositoryURL: repo, CommitSHA: head, Script: "echo started\nsleep 60\necho finished"})

	if elapsed > 15*time.Second {
		t.Errorf("cancellation took %s", elapsed)
	}
	if f.finish["cancelled"] != true || result != "canceled" {
		t.Errorf("finish = %v, result = %q", f.finish, result)
	}
	if log := f.log(); strings.Contains(log, "finished") || !strings.Contains(log, "cancelled") {
		t.Errorf("log:\n%s", log)
	}
}

func TestStopsAtTheTimeout(t *testing.T) {
	repo, _, head := repository(t)
	f := &fakeServer{}
	elapsed, result := runJob(t, f, job{RepositoryURL: repo, CommitSHA: head, TimeoutSeconds: 2, Script: "sleep 60"})

	if elapsed > 15*time.Second {
		t.Errorf("timeout took %s", elapsed)
	}
	if f.finish["exit_status"] != float64(1) || f.finish["cancelled"] != false || result != "failed" {
		t.Errorf("finish = %v, result = %q", f.finish, result)
	}
	if log := f.log(); !strings.Contains(log, "exceeded its timeout") {
		t.Errorf("log:\n%s", log)
	}
}

func TestCloneTokenIsScopedToTheRepositoryOrigin(t *testing.T) {
	t.Setenv("TUIST_RUNNER_REPORT_TOKEN", "leak")
	t.Setenv("GIT_CONFIG_COUNT", "5")
	env := strings.Join(cloneEnvironment(job{RepositoryURL: "https://git.example.com/acme/app.git", CloneToken: "clone-secret"}), "\n")

	for _, want := range []string{
		"GIT_CONFIG_COUNT=1",
		"GIT_CONFIG_KEY_0=http.https://git.example.com/.extraHeader",
		"GIT_CONFIG_VALUE_0=Authorization: Bearer clone-secret",
	} {
		if !strings.Contains(env, want) {
			t.Errorf("clone environment is missing %q", want)
		}
	}
	if strings.Contains(env, "leak") || strings.Contains(env, "GIT_CONFIG_COUNT=5") {
		t.Errorf("clone environment inherits runner variables:\n%s", env)
	}

	script := strings.Join(jobEnvironment(job{RepositoryURL: "https://git.example.com/acme/app.git", CloneToken: "clone-secret"}), "\n")
	if strings.Contains(script, "clone-secret") || strings.Contains(script, "leak") {
		t.Errorf("job environment carries a credential:\n%s", script)
	}
}
