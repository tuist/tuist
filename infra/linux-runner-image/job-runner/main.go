// tuist-job-runner executes a runner job created through the Tuist API.
//
// The server hands the claiming VM one job: a repository, a commit and a
// Bash script. This program checks the commit out, runs the script, streams
// its masked output to the job-scoped report endpoints and reports the exit
// status. Job outcomes exit 0, like tuist-gitlab-runner, because the
// runners-controller reads a non-zero exit as a runner death.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	maxLogBytes     = 64 * 1024 * 1024
	maxLogLines     = 1_000_000
	maxLineBytes    = 256 * 1024
	maxBatchLines   = 1000
	maxBatchBytes   = 512 * 1024
	killGracePeriod = 10 * time.Second
	masked          = "[MASKED]"
)

type job struct {
	WorkflowJobID  int64             `json:"workflow_job_id"`
	Name           string            `json:"name"`
	RepositoryURL  string            `json:"repository_url"`
	Ref            string            `json:"ref"`
	CommitSHA      string            `json:"commit_sha"`
	CloneToken     string            `json:"clone_token"`
	Script         string            `json:"script"`
	Env            map[string]string `json:"env"`
	Secrets        map[string]string `json:"secrets"`
	TimeoutSeconds int               `json:"timeout_seconds"`
	ReportToken    string            `json:"report_token"`
	ReportURL      string            `json:"report_url"`
}

type config struct {
	buildsDir     string
	resultFile    string
	flushInterval time.Duration
}

func main() {
	jobFile := flag.String("job-file", "", "Path to the staged job.")
	buildsDir := flag.String("builds-dir", "/home/runner/work", "Directory the repository is checked out under.")
	resultFile := flag.String("result-file", "", "Where to write succeeded, failed or canceled once the job ends.")
	flag.Parse()

	j, err := readJob(*jobFile)
	if err != nil {
		fmt.Fprintln(os.Stderr, "tuist-job-runner:", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	if err := run(ctx, j, config{buildsDir: *buildsDir, resultFile: *resultFile, flushInterval: 2 * time.Second}); err != nil {
		fmt.Fprintln(os.Stderr, "tuist-job-runner:", err)
		os.Exit(1)
	}
}

func readJob(path string) (job, error) {
	var j job
	content, err := os.ReadFile(path)
	if err != nil {
		return j, errors.New("job file could not be read")
	}
	// The script can read anything this user can, so drop the staged file
	// once it is in memory. Best effort: the directory may not be ours.
	_ = os.Remove(path)
	if err := json.Unmarshal(content, &j); err != nil {
		return j, errors.New("job file is not valid JSON")
	}
	if j.ReportURL == "" || j.ReportToken == "" || j.RepositoryURL == "" || j.CommitSHA == "" || j.Script == "" {
		return j, errors.New("job file is incomplete")
	}
	return j, nil
}

type outcome struct {
	exitStatus int
	cancelled  bool
}

func (o outcome) result() string {
	switch {
	case o.cancelled:
		return "canceled"
	case o.exitStatus == 0:
		return "succeeded"
	default:
		return "failed"
	}
}

// run executes the job and reports it. It returns an error only when the
// outcome could not be reported, which is a runner failure, not a job one.
func run(ctx context.Context, j job, cfg config) error {
	reporter := newReporter(j)
	log := newJobLog(j.Secrets)
	cancel := make(chan struct{})
	var cancelOnce sync.Once
	flusherDone := make(chan struct{})
	stopFlusher := make(chan struct{})

	go func() {
		defer close(flusherDone)
		ticker := time.NewTicker(cfg.flushInterval)
		defer ticker.Stop()
		for {
			select {
			case <-stopFlusher:
				return
			case <-ticker.C:
				if reporter.flush(log, true) {
					cancelOnce.Do(func() { close(cancel) })
				}
			}
		}
	}()

	o := execute(ctx, j, cfg, log, cancel)

	close(stopFlusher)
	<-flusherDone

	if cfg.resultFile != "" {
		_ = os.WriteFile(cfg.resultFile, []byte(o.result()+"\n"), 0o644)
	}

	// The finish report closes the billable window, so it goes before the
	// remaining log lines.
	finishErr := reporter.post("finish", map[string]any{"exit_status": o.exitStatus, "cancelled": o.cancelled}, nil)
	log.close()
	for reporter.pending(log) {
		if !reporter.flushOnce(log) {
			break
		}
	}
	if finishErr != nil {
		return fmt.Errorf("finish report failed: %w", finishErr)
	}
	return nil
}

func execute(ctx context.Context, j job, cfg config, log *jobLog, cancel <-chan struct{}) outcome {
	timeout := time.Duration(j.TimeoutSeconds) * time.Second
	if timeout <= 0 {
		timeout = time.Hour
	}
	deadline := time.Now().Add(timeout)

	fmt.Fprintf(log, "Running %s on Tuist Runners\n", displayName(j))
	checkout := filepath.Join(cfg.buildsDir, "job-"+strconv.FormatInt(j.WorkflowJobID, 10))
	fmt.Fprintf(log, "Checking out %s at %s\n", j.RepositoryURL, j.CommitSHA)
	if err := checkoutUnlessCancelled(ctx, j, checkout, log, deadline, cancel); err != nil {
		select {
		case <-cancel:
			fmt.Fprintln(log, "The job was cancelled.")
			return outcome{exitStatus: 1, cancelled: true}
		default:
			fmt.Fprintf(log, "Checkout failed: %s\n", err)
			return outcome{exitStatus: 1}
		}
	}

	script, err := os.CreateTemp(cfg.buildsDir, "tuist-job-*.sh")
	if err != nil {
		fmt.Fprintln(log, "The job script could not be written.")
		return outcome{exitStatus: 1}
	}
	defer os.Remove(script.Name())
	_, err = script.WriteString("set -eo pipefail\n" + j.Script + "\n")
	if closeErr := script.Close(); err != nil || closeErr != nil {
		fmt.Fprintln(log, "The job script could not be written.")
		return outcome{exitStatus: 1}
	}

	cmd := exec.Command("bash", "--login", script.Name())
	cmd.Dir = checkout
	cmd.Env = jobEnvironment(j)
	cmd.Stdout = log
	cmd.Stderr = log
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		fmt.Fprintln(log, "The job script could not be started.")
		return outcome{exitStatus: 1}
	}

	exited := make(chan error, 1)
	go func() { exited <- cmd.Wait() }()

	timer := time.NewTimer(time.Until(deadline))
	defer timer.Stop()

	select {
	case err := <-exited:
		return outcome{exitStatus: exitStatus(err)}
	case <-timer.C:
		fmt.Fprintf(log, "\nThe job exceeded its timeout of %s and was stopped.\n", timeout)
		stopProcessGroup(cmd, exited)
		return outcome{exitStatus: 1}
	case <-cancel:
		fmt.Fprintln(log, "\nThe job was cancelled.")
		stopProcessGroup(cmd, exited)
		return outcome{exitStatus: 1, cancelled: true}
	case <-ctx.Done():
		fmt.Fprintln(log, "\nThe runner is shutting down; the job was stopped.")
		stopProcessGroup(cmd, exited)
		return outcome{exitStatus: 1}
	}
}

func displayName(j job) string {
	if j.Name != "" {
		return j.Name
	}
	return "job"
}

func stopProcessGroup(cmd *exec.Cmd, exited <-chan error) {
	_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
	select {
	case <-exited:
	case <-time.After(killGracePeriod):
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		<-exited
	}
}

func exitStatus(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) && exitErr.ExitCode() > 0 {
		return exitErr.ExitCode()
	}
	return 1
}

func checkoutUnlessCancelled(ctx context.Context, j job, dir string, log io.Writer, deadline time.Time, cancel <-chan struct{}) error {
	ctx, stop := context.WithCancel(ctx)
	defer stop()
	go func() {
		select {
		case <-cancel:
			stop()
		case <-ctx.Done():
		}
	}()
	return checkoutRepository(ctx, j, dir, log, deadline)
}

// checkoutRepository fetches only the job's commit. Servers that refuse
// fetching an unadvertised SHA get the ref instead, which must contain it.
func checkoutRepository(ctx context.Context, j job, dir string, log io.Writer, deadline time.Time) error {
	ctx, cancel := context.WithDeadline(ctx, deadline)
	defer cancel()

	if err := os.RemoveAll(dir); err != nil {
		return errors.New("the checkout directory could not be cleared")
	}
	gitEnv := cloneEnvironment(j)
	git := func(args ...string) error {
		cmd := exec.CommandContext(ctx, "git", args...)
		cmd.Env = gitEnv
		cmd.Stdout = log
		cmd.Stderr = log
		return cmd.Run()
	}

	if err := git("init", "--quiet", dir); err != nil {
		return errors.New("git init failed")
	}
	if err := git("-C", dir, "remote", "add", "origin", j.RepositoryURL); err != nil {
		return errors.New("the remote could not be added")
	}
	if err := git("-C", dir, "fetch", "--quiet", "--no-tags", "--depth=1", "origin", j.CommitSHA); err != nil {
		if j.Ref == "" {
			return errors.New("the commit could not be fetched")
		}
		fmt.Fprintf(log, "Fetching %s instead\n", j.Ref)
		if err := git("-C", dir, "fetch", "--quiet", "--no-tags", "origin", j.Ref); err != nil {
			return errors.New("the ref could not be fetched")
		}
	}
	if err := git("-C", dir, "-c", "advice.detachedHead=false", "checkout", "--quiet", "--detach", j.CommitSHA); err != nil {
		return errors.New("the commit could not be checked out")
	}
	return nil
}

// cloneEnvironment scopes the clone token to the repository's origin through
// git's URL-matched config, so it is never on a command line, in the remote
// URL or in the script's environment.
func cloneEnvironment(j job) []string {
	env := append(baseEnvironment(), "GIT_TERMINAL_PROMPT=0")
	if j.CloneToken == "" {
		return env
	}
	parsed, err := url.Parse(j.RepositoryURL)
	if err != nil || parsed.Host == "" {
		return env
	}
	origin := parsed.Scheme + "://" + parsed.Host + "/"
	return append(env,
		"GIT_CONFIG_COUNT=1",
		"GIT_CONFIG_KEY_0=http."+origin+".extraHeader",
		"GIT_CONFIG_VALUE_0=Authorization: Bearer "+j.CloneToken,
	)
}

// baseEnvironment drops the runner's own report credentials and any git
// config injection inherited from the image.
func baseEnvironment() []string {
	var env []string
	for _, entry := range os.Environ() {
		name, _, _ := strings.Cut(entry, "=")
		if strings.HasPrefix(name, "TUIST_RUNNER_") || strings.HasPrefix(name, "GIT_CONFIG_") {
			continue
		}
		env = append(env, entry)
	}
	return env
}

func jobEnvironment(j job) []string {
	env := append(baseEnvironment(),
		"CI=true",
		"TUIST_JOB_ID="+strconv.FormatInt(j.WorkflowJobID, 10),
		"TUIST_JOB_NAME="+j.Name,
		"TUIST_JOB_REPOSITORY_URL="+j.RepositoryURL,
		"TUIST_JOB_REF="+j.Ref,
		"TUIST_JOB_COMMIT_SHA="+j.CommitSHA,
	)
	for name, value := range j.Env {
		env = append(env, name+"="+value)
	}
	for name, value := range j.Secrets {
		env = append(env, name+"="+value)
	}
	return env
}

// jobLog splits output into lines, masks secrets, stamps each line with the
// time it was read and holds lines until the reporter takes them. The
// timestamp uses the marker `Tuist.Runners.Buildkite.LogParser` reads.
type jobLog struct {
	mu       sync.Mutex
	partial  []byte
	lines    []string
	bytes    int
	count    int
	full     bool
	closed   bool
	replacer *strings.Replacer
	now      func() time.Time
}

func newJobLog(secrets map[string]string) *jobLog {
	var pairs []string
	for _, value := range secrets {
		for _, part := range strings.Split(value, "\n") {
			part = strings.TrimSpace(part)
			if len(part) >= 3 {
				pairs = append(pairs, part, masked)
			}
		}
	}
	return &jobLog{replacer: strings.NewReplacer(pairs...), now: time.Now}
}

func (l *jobLog) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.closed {
		return len(p), nil
	}
	l.partial = append(l.partial, p...)
	for {
		index := bytes.IndexByte(l.partial, '\n')
		if index < 0 {
			break
		}
		l.appendLine(string(l.partial[:index]))
		l.partial = l.partial[index+1:]
	}
	if len(l.partial) > maxLineBytes {
		l.appendLine(string(l.partial))
		l.partial = nil
	}
	return len(p), nil
}

func (l *jobLog) appendLine(line string) {
	if l.full {
		return
	}
	line = strings.TrimSuffix(line, "\r")
	if len(line) > maxLineBytes {
		line = line[:maxLineBytes] + " [line truncated]"
	}
	line = l.replacer.Replace(line)
	if l.bytes+len(line) > maxLogBytes || l.count+1 >= maxLogLines {
		l.full = true
		line = "[The log reached its size limit; later output is not recorded.]"
	}
	l.lines = append(l.lines, fmt.Sprintf("\x1b_bk;t=%d\x07%s", l.now().UnixMilli(), line))
	l.bytes += len(line)
	l.count++
}

// close takes a final unterminated line and stops accepting output.
func (l *jobLog) close() {
	l.mu.Lock()
	defer l.mu.Unlock()
	if len(l.partial) > 0 {
		l.appendLine(string(l.partial))
		l.partial = nil
	}
	l.closed = true
}

// take returns the next batch and the line number of its first line, without
// removing it, so a failed post is retried with the same lines.
func (l *jobLog) take() ([]string, int) {
	l.mu.Lock()
	defer l.mu.Unlock()
	end, size := 0, 0
	for end < len(l.lines) && end < maxBatchLines && (size < maxBatchBytes || end == 0) {
		size += len(l.lines[end])
		end++
	}
	// Never nil: an empty poll must still send `"lines": []`.
	batch := append(make([]string, 0, end), l.lines[:end]...)
	return batch, l.count - len(l.lines) + 1
}

func (l *jobLog) drop(n int) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.lines = l.lines[n:]
}

func (l *jobLog) hasPending() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.lines) > 0
}

type reporter struct {
	job    job
	client *http.Client
}

func newReporter(j job) *reporter {
	return &reporter{job: j, client: &http.Client{
		Timeout:       20 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}}
}

func (r *reporter) pending(log *jobLog) bool { return log.hasPending() }

// flush posts every pending batch, or one empty batch so the server can
// answer with a cancellation, and reports whether it asked to cancel.
func (r *reporter) flush(log *jobLog, poll bool) bool {
	cancelRequested := false
	posted := false
	for log.hasPending() || (poll && !posted) {
		batch, first := log.take()
		var response struct {
			CancelRequested bool `json:"cancel_requested"`
		}
		if err := r.post("logs", map[string]any{"lines": batch, "first_line_number": first}, &response); err != nil {
			return cancelRequested
		}
		log.drop(len(batch))
		posted = true
		cancelRequested = cancelRequested || response.CancelRequested
	}
	return cancelRequested
}

func (r *reporter) flushOnce(log *jobLog) bool {
	batch, first := log.take()
	if err := r.post("logs", map[string]any{"lines": batch, "first_line_number": first}, nil); err != nil {
		return false
	}
	log.drop(len(batch))
	return true
}

func (r *reporter) post(endpoint string, body any, into any) error {
	encoded, err := json.Marshal(body)
	if err != nil {
		return err
	}
	var lastErr error
	for attempt := 0; attempt < 5; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(attempt) * time.Second)
		}
		request, err := http.NewRequest(http.MethodPost, strings.TrimRight(r.job.ReportURL, "/")+"/"+endpoint, bytes.NewReader(encoded))
		if err != nil {
			return err
		}
		request.Header.Set("Authorization", "Bearer "+r.job.ReportToken)
		request.Header.Set("Content-Type", "application/json")
		response, err := r.client.Do(request)
		if err != nil {
			lastErr = errors.New("report request failed")
			continue
		}
		content, _ := io.ReadAll(io.LimitReader(response.Body, 64*1024))
		response.Body.Close()
		switch {
		case response.StatusCode >= 200 && response.StatusCode < 300:
			if into != nil && len(content) > 0 {
				_ = json.Unmarshal(content, into)
			}
			return nil
		case response.StatusCode >= 400 && response.StatusCode < 500 && response.StatusCode != 429:
			return fmt.Errorf("report rejected with status %d", response.StatusCode)
		default:
			lastErr = fmt.Errorf("report failed with status %d", response.StatusCode)
		}
	}
	return lastErr
}
