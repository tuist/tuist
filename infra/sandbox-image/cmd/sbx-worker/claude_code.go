package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// Claude Code mode: sandboxd or the macOS host starts sbx-worker with
// SBX_CLAUDE_CODE_WORK_ORDER, the single-use work order Anthropic minted for
// one Claude Code cloud session, and sbx-worker runs `claude
// self-hosted-runner` with it. The runner registers, claims that session,
// clones its repository through Anthropic's git proxy and exits once the
// session is released, which ends the residency like a Managed Agents worker.
const (
	claudeCodeWorkOrderEnv = "SBX_CLAUDE_CODE_WORK_ORDER"
	claudeCodeVersion      = "2.1.311"
	claudeCodeDownloadBase = "https://downloads.claude.ai/claude-code-releases"
	// The Linux template bakes this exact build in; the macOS runner image does
	// not, so the first session of a macOS sandbox copies it under $HOME from
	// the host's tools share (tart-kubelet's provisionClaudeCode), or downloads
	// it when the host has not fetched it yet.
	claudeCodeBakedPath = "/usr/local/bin/claude"
	// Linux execs run as root, which Claude Code refuses to bypass permissions
	// as; the runner runs as the template's unprivileged user instead.
	claudeCodeLinuxUser = "user"
)

// Published in the release's manifest.json.
var claudeCodeChecksums = map[string]string{
	"darwin-arm64": "85d8c08707fcfd1e78ffa0204eefbc6ec9e4fe22f375fb2767ef85d957ed3161",
	"darwin-x64":   "d34e1cb82015b050471a97574aa6ea6f698ecf3a97a61c980961f43ad9f838f5",
	"linux-arm64":  "2e2496c9a8065df93acb0fca2d341f59a6b8777649b2e025ab8c9bcd5eef61f3",
	"linux-x64":    "86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada",
}

type claudeCodeOptions struct {
	binary string
	// execPath, when set, is the session wrapper the runner starts in place
	// of the Claude Code binary (execSession).
	execPath       string
	baseDir        string
	workOrder      string
	label          string
	releaseIdleMin int
	killAfterMin   int
}

// runnerCommand is the runner invocation: one session, Anthropic-managed git,
// no health listener, and the work order passed only in the environment.
func runnerCommand(opts claudeCodeOptions, environ []string) (args []string, env []string) {
	args = []string{
		"self-hosted-runner",
		"--base-dir", opts.baseDir,
		"--capacity", "1",
		"--use-anthropic-git-proxy",
		"--release-idle-session-min", strconv.Itoa(opts.releaseIdleMin),
		"--kill-session-after-min", strconv.Itoa(opts.killAfterMin),
		"--exit-if-unused-min", "10",
		"--health-port", "0",
		"--client-label", opts.label,
	}
	if opts.execPath != "" {
		args = append(args, "--exec-path", opts.execPath)
	}
	for _, kv := range environ {
		key, _, _ := strings.Cut(kv, "=")
		if key == claudeCodeWorkOrderEnv || key == "SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET" {
			continue
		}
		env = append(env, kv)
	}
	env = append(env, "SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET="+opts.workOrder)
	return args, env
}

func runClaudeCode(ctx context.Context, logger *slog.Logger, workdir, workOrder string) int {
	releaseIdleMin, err := minutesEnv("SBX_CLAUDE_CODE_RELEASE_IDLE_MIN", 30)
	if err != nil {
		logger.Error("invalid SBX_CLAUDE_CODE_RELEASE_IDLE_MIN", slog.Any("error", err))
		return 1
	}
	killAfterMin, err := minutesEnv("SBX_CLAUDE_CODE_KILL_AFTER_MIN", 720)
	if err != nil {
		logger.Error("invalid SBX_CLAUDE_CODE_KILL_AFTER_MIN", slog.Any("error", err))
		return 1
	}

	credential, home, err := runnerIdentity()
	if err != nil {
		logger.Error("claude code runner user unavailable", slog.Any("error", err))
		return 1
	}
	baseDir := filepath.Join(workdir, "claude-code")
	if err := os.MkdirAll(baseDir, 0o755); err != nil {
		logger.Error("claude code base dir", slog.Any("error", err))
		return 1
	}
	if credential != nil {
		if err := os.Chown(baseDir, int(credential.Uid), int(credential.Gid)); err != nil {
			logger.Error("claude code base dir owner", slog.Any("error", err))
			return 1
		}
	}

	binary, err := claudeBinary(ctx, home, claudeCodeDownloadBase)
	if err != nil {
		logger.Error("claude code unavailable", slog.Any("error", err))
		return 1
	}

	// A failed checkout only costs the runner its clone, so it never stops the session.
	checkout, err := checkoutFromEnv(baseDir, credential)
	if err != nil {
		logger.Warn("checkout grant unusable", slog.Any("error", err))
	}
	if checkout != nil {
		start := time.Now()
		result, err := checkout.seed(ctx)
		if err != nil {
			logger.Warn("checkout seed failed", slog.Any("error", err), slog.Duration("duration", time.Since(start)))
		} else {
			logger.Info("checkout seeded", slog.String("result", result), slog.Duration("duration", time.Since(start)))
		}
		defer func() {
			start := time.Now()
			result, err := checkout.export(context.WithoutCancel(ctx))
			if err != nil {
				logger.Warn("checkout export failed", slog.Any("error", err), slog.Duration("duration", time.Since(start)))
				return
			}
			logger.Info("checkout export", slog.String("result", result), slog.Duration("duration", time.Since(start)))
		}()
	}

	// Only a sandbox wired to Tuist needs the wrapper. It is this binary,
	// root-owned like the rest of the guest tools, so session code cannot
	// change what the runner starts.
	execPath := ""
	if os.Getenv("TUIST_URL") != "" {
		if self, err := os.Executable(); err == nil {
			execPath = self
		}
	}

	hostname, _ := os.Hostname()
	args, env := runnerCommand(claudeCodeOptions{
		binary:         binary,
		execPath:       execPath,
		baseDir:        baseDir,
		workOrder:      workOrder,
		label:          hostname,
		releaseIdleMin: releaseIdleMin,
		killAfterMin:   killAfterMin,
	}, os.Environ())
	if credential != nil {
		env = append(env, "HOME="+home, "USER="+claudeCodeLinuxUser, "LOGNAME="+claudeCodeLinuxUser)
	}

	cmd := exec.Command(binary, args...)
	cmd.Dir = baseDir
	cmd.Env = env
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{Credential: credential}
	if err := cmd.Start(); err != nil {
		logger.Error("claude code runner failed to start", slog.Any("error", err))
		return 1
	}
	logger.Info("claude code runner started", slog.String("base_dir", baseDir), slog.String("version", claudeCodeVersion))

	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err = <-done:
	case <-ctx.Done():
		// stop_worker: the runner drains its session and exits on SIGTERM.
		_ = cmd.Process.Signal(syscall.SIGTERM)
		err = <-done
	}
	var exit *exec.ExitError
	switch {
	case err == nil:
		logger.Info("claude code runner finished")
		return 0
	case errors.As(err, &exit):
		logger.Error("claude code runner exited", slog.Int("exit_code", exit.ExitCode()))
		return 1
	default:
		logger.Error("claude code runner failed", slog.Any("error", err))
		return 1
	}
}

// sessionEnvironment is the environment the session wrapper starts Claude Code
// with. In a sandbox wired to Tuist, Tuist clients sign in by exchanging the
// session's own identity token, which Anthropic hands the wrapper; Tuist
// accepts it for sessions of a Claude Code environment an account connected.
// The token is the one at spawn time, valid for four hours by default.
func sessionEnvironment(environ []string) []string {
	values := map[string]string{}
	for _, kv := range environ {
		key, value, _ := strings.Cut(kv, "=")
		values[key] = value
	}
	token := values["CLAUDE_CODE_SESSION_ACCESS_TOKEN"]
	if values["TUIST_URL"] == "" || values["TUIST_OIDC_TOKEN"] != "" || !strings.HasPrefix(token, "sk-ant-cc-") {
		return environ
	}
	return append(slices.Clone(environ), "TUIST_OIDC_TOKEN="+token)
}

// execSession is the session wrapper: the runner starts it in place of Claude
// Code with CLAUDE_RUNNER_CLAUDE_BIN, and it replaces itself with that binary,
// so stdin, file descriptor 3, signals and the exit code stay the runner's.
func execSession(claudeBin string, args []string) error {
	return syscall.Exec(claudeBin, append([]string{claudeBin}, args...), sessionEnvironment(os.Environ()))
}

func minutesEnv(name string, fallback int) (int, error) {
	raw := os.Getenv(name)
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value < 1 {
		return 0, fmt.Errorf("%q is not a positive number of minutes", raw)
	}
	return value, nil
}

// runnerIdentity is nil (keep this process's user) except for root on Linux.
func runnerIdentity() (*syscall.Credential, string, error) {
	home, _ := os.UserHomeDir()
	if runtime.GOOS != "linux" || os.Geteuid() != 0 {
		return nil, home, nil
	}
	account, err := user.Lookup(claudeCodeLinuxUser)
	if err != nil {
		return nil, "", err
	}
	uid, err := strconv.ParseUint(account.Uid, 10, 32)
	if err != nil {
		return nil, "", err
	}
	gid, err := strconv.ParseUint(account.Gid, 10, 32)
	if err != nil {
		return nil, "", err
	}
	return &syscall.Credential{Uid: uint32(uid), Gid: uint32(gid)}, account.HomeDir, nil
}

func claudePlatform() string {
	arch := map[string]string{"amd64": "x64", "arm64": "arm64"}[runtime.GOARCH]
	return runtime.GOOS + "-" + arch
}

// The macOS host shares the pinned build at claude-code/<version>/claude. A
// guest cannot execute from the share after a resume, so it is copied.
var claudeCodeSharedDir = "/Volumes/My Shared Files/sandbox-tools/claude-code"

// claudeBinary returns the pinned build: the template's copy when it is that
// build, else one copied once into home from the host's share or downloaded,
// either verified against the release checksum.
func claudeBinary(ctx context.Context, home, downloadBase string) (string, error) {
	platform := claudePlatform()
	checksum, ok := claudeCodeChecksums[platform]
	if !ok {
		return "", fmt.Errorf("no claude code build for %s", platform)
	}
	if fileSHA256(claudeCodeBakedPath) == checksum {
		return claudeCodeBakedPath, nil
	}
	path := filepath.Join(home, ".local", "share", "tuist-sandbox", "claude", claudeCodeVersion, "claude")
	if fileSHA256(path) == checksum {
		return path, nil
	}
	if err := copyVerified(filepath.Join(claudeCodeSharedDir, claudeCodeVersion, "claude"), checksum, path); err == nil {
		return path, nil
	}
	if err := downloadVerified(ctx, fmt.Sprintf("%s/%s/%s/claude", downloadBase, claudeCodeVersion, platform), checksum, path); err != nil {
		return "", err
	}
	return path, nil
}

func fileSHA256(path string) string {
	file, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return ""
	}
	return hex.EncodeToString(hash.Sum(nil))
}

// copyVerified copies source to path only when its content hashes to checksum.
func copyVerified(source, checksum, path string) error {
	file, err := os.Open(source)
	if err != nil {
		return err
	}
	defer file.Close()
	return writeVerified(file, source, checksum, path)
}

// downloadVerified writes url to path only when its content hashes to checksum.
func downloadVerified(ctx context.Context, url, checksum, path string) error {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("download %s: HTTP %d", url, response.StatusCode)
	}
	return writeVerified(response.Body, url, checksum, path)
}

func writeVerified(content io.Reader, source, checksum, path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	partial, err := os.CreateTemp(filepath.Dir(path), ".claude-*")
	if err != nil {
		return err
	}
	defer os.Remove(partial.Name())
	hash := sha256.New()
	_, err = io.Copy(io.MultiWriter(partial, hash), content)
	if closeErr := partial.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	if got := hex.EncodeToString(hash.Sum(nil)); got != checksum {
		return fmt.Errorf("%s: checksum %s, want %s", source, got, checksum)
	}
	if err := os.Chmod(partial.Name(), 0o755); err != nil {
		return err
	}
	return os.Rename(partial.Name(), path)
}
