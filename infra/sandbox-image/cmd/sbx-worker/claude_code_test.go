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
