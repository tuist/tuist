package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestRunnerCommandPassesTheWorkOrderOnlyAsTheRunnerSecret(t *testing.T) {
	args, env := runnerCommand(claudeCodeOptions{
		baseDir:        "/workspace/claude-code",
		workOrder:      "jwt.order",
		label:          "sbx-1",
		releaseIdleMin: 15,
		killAfterMin:   600,
	}, []string{"PATH=/usr/bin", claudeCodeWorkOrderEnv + "=jwt.order", "SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET=stale"})

	want := []string{
		"self-hosted-runner", "--base-dir", "/workspace/claude-code", "--capacity", "1", "--use-anthropic-git-proxy",
		"--release-idle-session-min", "15", "--kill-session-after-min", "600", "--exit-if-unused-min", "10",
		"--health-port", "0", "--client-label", "sbx-1",
	}
	if !slices.Equal(args, want) {
		t.Fatalf("args = %q, want %q", args, want)
	}
	if strings.Contains(strings.Join(args, " "), "jwt.order") {
		t.Fatalf("work order in argv: %q", args)
	}
	wantEnv := []string{"PATH=/usr/bin", "SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET=jwt.order"}
	if !slices.Equal(env, wantEnv) {
		t.Fatalf("env = %q, want %q", env, wantEnv)
	}
}

func TestDownloadVerifiedRefusesContentThatDoesNotMatchTheChecksum(t *testing.T) {
	served := []byte("claude build")
	sum := sha256.Sum256(served)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write(served) }))
	defer server.Close()
	path := filepath.Join(t.TempDir(), "claude", "claude")

	if err := downloadVerified(context.Background(), server.URL, strings.Repeat("0", 64), path); err == nil {
		t.Fatal("a mismatching download was accepted")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("a mismatching download was left at %s", path)
	}

	if err := downloadVerified(context.Background(), server.URL, hex.EncodeToString(sum[:]), path); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0o755 {
		t.Fatalf("verified download at %s: %v %v", path, info, err)
	}
}

func TestClaudeBinaryCopiesTheHostSharedBuildInsteadOfDownloading(t *testing.T) {
	build := []byte("pinned claude build")
	sum := sha256.Sum256(build)
	platform := claudePlatform()
	checksum, shared := claudeCodeChecksums[platform], claudeCodeSharedDir
	claudeCodeChecksums[platform] = hex.EncodeToString(sum[:])
	claudeCodeSharedDir = t.TempDir()
	defer func() { claudeCodeChecksums[platform], claudeCodeSharedDir = checksum, shared }()
	downloads := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		downloads++
		_, _ = w.Write(build)
	}))
	defer server.Close()

	// A shared build that is not the pinned one is ignored.
	sharedPath := filepath.Join(claudeCodeSharedDir, claudeCodeVersion, "claude")
	if err := os.MkdirAll(filepath.Dir(sharedPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(sharedPath, []byte("another build"), 0o644); err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	if _, err := claudeBinary(context.Background(), home, server.URL); err != nil || downloads != 1 {
		t.Fatalf("mismatching share: err=%v downloads=%d", err, downloads)
	}

	if err := os.WriteFile(sharedPath, build, 0o644); err != nil {
		t.Fatal(err)
	}
	home = t.TempDir()
	path, err := claudeBinary(context.Background(), home, server.URL)
	if err != nil || downloads != 1 {
		t.Fatalf("pinned share: err=%v downloads=%d", err, downloads)
	}
	if !strings.HasPrefix(path, home) || fileSHA256(path) != hex.EncodeToString(sum[:]) {
		t.Fatalf("binary at %s is not a verified copy under home", path)
	}
	if info, err := os.Stat(path); err != nil || info.Mode().Perm() != 0o755 {
		t.Fatalf("copied binary mode: %v %v", info, err)
	}
}

func TestRunnerStartsTheSessionWrapperOnlyWhenGiven(t *testing.T) {
	args, _ := runnerCommand(claudeCodeOptions{baseDir: "/workspace/claude-code", execPath: "/usr/local/bin/sbx-worker"}, nil)
	if !slices.Contains(args, "--exec-path") || args[len(args)-1] != "/usr/local/bin/sbx-worker" {
		t.Fatalf("args = %q", args)
	}
	args, _ = runnerCommand(claudeCodeOptions{baseDir: "/workspace/claude-code"}, nil)
	if slices.Contains(args, "--exec-path") {
		t.Fatalf("args = %q", args)
	}
}

func TestSessionEnvironmentHandsTuistTheSessionToken(t *testing.T) {
	token := "sk-ant-cc-header.payload.signature"
	base := []string{"PATH=/usr/bin", "CLAUDE_CODE_SESSION_ACCESS_TOKEN=" + token}
	cases := map[string]struct {
		environ []string
		want    string
	}{
		"wired to Tuist":       {append(slices.Clone(base), "TUIST_URL=https://tuist.dev"), token},
		"not wired to Tuist":   {base, ""},
		"a token already set":  {append(slices.Clone(base), "TUIST_URL=https://tuist.dev", "TUIST_OIDC_TOKEN=mine"), "mine"},
		"not a session token":  {[]string{"TUIST_URL=https://tuist.dev", "CLAUDE_CODE_SESSION_ACCESS_TOKEN=sk-ant-si-x.y.z"}, ""},
		"no session token set": {[]string{"TUIST_URL=https://tuist.dev"}, ""},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			env := sessionEnvironment(tc.environ)
			got := ""
			count := 0
			for _, kv := range env {
				if value, ok := strings.CutPrefix(kv, "TUIST_OIDC_TOKEN="); ok {
					got = value
					count++
				}
			}
			if got != tc.want || count > 1 {
				t.Fatalf("TUIST_OIDC_TOKEN = %q (%d times), want %q", got, count, tc.want)
			}
			if !slices.Equal(env[:len(tc.environ)], tc.environ) {
				t.Fatalf("the rest of the environment changed: %q", env)
			}
		})
	}
}
