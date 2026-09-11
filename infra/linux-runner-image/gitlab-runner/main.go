// tuist-gitlab-runner executes an assignment acquired by the Tuist server.
// The reusable GitLab runner token is deliberately absent from its input.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/urfave/cli"
	"gitlab.com/gitlab-org/gitlab-runner/commands/helpers"
	"gitlab.com/gitlab-org/gitlab-runner/common"
	"gitlab.com/gitlab-org/gitlab-runner/common/spec"
	"gitlab.com/gitlab-org/gitlab-runner/executors"
	"gitlab.com/gitlab-org/gitlab-runner/executors/shell"
	"gitlab.com/gitlab-org/gitlab-runner/network"
	_ "gitlab.com/gitlab-org/gitlab-runner/shells"
)

const maxLogBytes = 64 * 1024 * 1024

type assignment struct {
	URL         string   `json:"url"`
	Payload     spec.Job `json:"payload"`
	ReportToken string   `json:"report_token"`
	ReportURL   string   `json:"report_url"`
}

// GitLab's build logger masks variables and credentials before writing to
// JobTrace. Capture at that same boundary, with a bounded, private local file.
type jobTrace struct {
	common.JobTrace
	mu        sync.Mutex
	log       *os.File
	written   int
	exitCode  int
	cancelled bool
	finished  bool
}

func (t *jobTrace) Write(p []byte) (int, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if remaining := maxLogBytes - t.written; remaining > 0 {
		n, _ := t.log.Write(p[:min(len(p), remaining)])
		t.written += n
	}
	return t.JobTrace.Write(p)
}

func (t *jobTrace) Fail(err error, data common.JobFailureData) error {
	t.mu.Lock()
	t.exitCode = data.ExitCode
	t.cancelled = errors.Is(err, common.ErrJobCanceled) || data.Reason == "job_canceled"
	if t.exitCode == 0 {
		t.exitCode = 1
	}
	t.mu.Unlock()
	return t.JobTrace.Fail(err, data)
}

func (t *jobTrace) Finish() {
	t.mu.Lock()
	t.finished = true
	t.mu.Unlock()
	t.JobTrace.Finish()
}

func (t *jobTrace) Cancel() bool {
	t.mu.Lock()
	t.cancelled = true
	t.mu.Unlock()
	return t.JobTrace.Cancel()
}

func execute(job assignment, buildsDir string) error {
	if job.URL == "" || job.Payload.ID <= 0 || job.Payload.Token == "" || job.ReportToken == "" || job.ReportURL == "" {
		return errors.New("incomplete GitLab assignment")
	}
	command, err := os.Executable()
	if err != nil {
		return err
	}
	provider := shell.NewProvider(command)
	providers := executors.NewProviderRegistry(map[string]common.ExecutorProvider{"shell": provider})
	client := network.NewGitLabClient(network.WithExecutorProviderFunc(providers.GetByName))
	config := common.RunnerConfig{
		Name: "tuist", OutputLimit: maxLogBytes / 1024,
		RunnerCredentials: common.RunnerCredentials{URL: job.URL, Token: "job-scoped"},
		RunnerSettings: common.RunnerSettings{
			Executor: "shell", Shell: "bash", BuildsDir: buildsDir,
			CacheDir: filepath.Join(buildsDir, ".gitlab-cache"),
		},
	}
	credentials := &common.JobCredentials{ID: job.Payload.ID, Token: job.Payload.Token}
	upstreamTrace, err := client.ProcessJob(config, credentials)
	if err != nil {
		return errors.New("could not initialize GitLab job trace")
	}
	logFile, err := os.CreateTemp("", "tuist-gitlab-log-*")
	if err != nil {
		upstreamTrace.Finish()
		return err
	}
	defer os.Remove(logFile.Name())
	defer logFile.Close()
	trace := &jobTrace{JobTrace: upstreamTrace, log: logFile}
	defer func() {
		// This is idempotent in GitLab Runner when Build.Run already failed.
		trace.mu.Lock()
		finished := trace.finished
		trace.mu.Unlock()
		if !finished {
			_ = trace.Success()
		}
		trace.mu.Lock()
		outcome := map[string]any{"exit_status": trace.exitCode, "cancelled": trace.cancelled}
		trace.mu.Unlock()
		if err := report(job, "finish", outcome); err != nil {
			fmt.Fprintln(os.Stderr, "Tuist job completion report failed")
		}
		if err := reportLog(job, logFile); err != nil {
			fmt.Fprintln(os.Stderr, "Tuist job log report failed")
		}
	}()

	abort := make(chan os.Signal, 1)
	signal.Notify(abort, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(abort)
	data, err := provider.Acquire(&config)
	if err != nil {
		_ = trace.Fail(err, common.JobFailureData{Reason: "runner_system_failure"})
		return err
	}
	defer provider.Release(&config, data)
	build, err := common.NewBuild(job.Payload, &config, abort, data, provider)
	if err != nil {
		_ = trace.Fail(err, common.JobFailureData{Reason: "runner_system_failure"})
		return err
	}
	trace.SetDebugModeEnabled(build.IsDebugModeEnabled())
	result := client.UpdateJob(config, credentials, common.UpdateJobInfo{ID: job.Payload.ID, State: common.Running})
	if result.State == common.UpdateAbort || result.CancelRequested {
		trace.mu.Lock()
		trace.cancelled = true
		trace.exitCode = 1
		trace.mu.Unlock()
		trace.Finish()
		return nil
	}
	err = build.Run(common.NewConfig(), trace)
	var buildError *common.BuildError
	if errors.As(err, &buildError) {
		// Job outcomes are already reported. Reserve non-zero runner exits
		// for infrastructure failures, as required by the fleet controller.
		switch buildError.FailureReason {
		case "", common.ScriptFailure, common.JobCanceled, common.JobExecutionTimeout, common.ConfigurationError:
			return nil
		}
	}
	return err
}

func report(job assignment, endpoint string, body any) error {
	encoded, err := json.Marshal(body)
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: 20 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}}
	for attempt := 0; attempt < 3; attempt++ {
		request, err := http.NewRequest(http.MethodPost, strings.TrimRight(job.ReportURL, "/")+"/"+endpoint, bytes.NewReader(encoded))
		if err != nil {
			return err
		}
		request.Header.Set("Authorization", "Bearer "+job.ReportToken)
		request.Header.Set("Content-Type", "application/json")
		response, err := client.Do(request)
		if err == nil {
			_, _ = io.Copy(io.Discard, response.Body)
			response.Body.Close()
			if response.StatusCode >= 200 && response.StatusCode < 300 {
				return nil
			}
			if response.StatusCode >= 400 && response.StatusCode < 500 && response.StatusCode != 429 {
				return errors.New("report rejected")
			}
		}
		time.Sleep(time.Duration(attempt+1) * time.Second)
	}
	return errors.New("report retries exhausted")
}

func reportLog(job assignment, file *os.File) error {
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return err
	}
	content, err := io.ReadAll(io.LimitReader(file, maxLogBytes))
	if err != nil {
		return err
	}
	lines := strings.SplitN(strings.TrimSuffix(string(content), "\n"), "\n", 1_000_001)
	if len(lines) > 1_000_000 {
		lines = lines[:1_000_000]
	}
	for i, line := range lines {
		if len(line) > 256*1024 {
			lines[i] = line[:256*1024] + " [line truncated]"
		}
	}
	for first := 0; first < len(lines); {
		end, size := first, 0
		for end < len(lines) && end-first < 1000 && (size < 512*1024 || end == first) {
			size += len(lines[end])
			end++
		}
		if err := report(job, "logs", map[string]any{"lines": lines[first:end], "first_line_number": first + 1}); err != nil {
			return err
		}
		first = end
	}
	return nil
}

func main() {
	common.AppVersion.Version = "18.11.1"
	app := cli.NewApp()
	app.Name = "tuist-gitlab-runner"
	app.Version = common.AppVersion.ShortLine()
	app.Flags = []cli.Flag{cli.StringFlag{Name: "job-file"}, cli.StringFlag{Name: "builds-dir", Value: "work"}}
	// The shell executor invokes these commands on its own executable for
	// artifact and cache operations, exactly as the upstream runner does.
	app.Commands = []cli.Command{
		helpers.NewArtifactsDownloaderCommand(), helpers.NewArtifactsUploaderCommand(),
		helpers.NewCacheArchiverCommand(), helpers.NewCacheExtractorCommand(),
		helpers.NewCacheInitCommand(), helpers.NewProxyExecCommand(),
	}
	app.Action = func(ctx *cli.Context) error {
		file, err := os.Open(ctx.String("job-file"))
		if err != nil {
			return errors.New("could not open GitLab assignment")
		}
		defer file.Close()
		var job assignment
		if err := json.NewDecoder(io.LimitReader(file, 32*1024*1024)).Decode(&job); err != nil {
			return errors.New("invalid GitLab assignment")
		}
		return execute(job, ctx.String("builds-dir"))
	}
	if err := app.Run(os.Args); err != nil {
		// Errors from the executor may include repository URLs or job data.
		// GitLab's masked trace carries the detailed diagnostic instead.
		fmt.Fprintln(os.Stderr, "GitLab job execution failed")
		os.Exit(1)
	}
}
