package main

import "testing"

func TestSessionWebSocketURLUsesDiscoveryOrigin(t *testing.T) {
	t.Setenv("TUIST_RUNNER_SHELL_USE_DISCOVERY_ORIGIN", "")

	got, err := sessionWebSocketURL(
		runnerSession{WebSocketURL: "ws://public.example.com/api/internal/runners/interactive/shell/1/tunnel?token=abc"},
		"https://internal.example.com/api/internal/runners/interactive/shell/sessions",
	)
	if err != nil {
		t.Fatal(err)
	}

	want := "wss://internal.example.com/api/internal/runners/interactive/shell/1/tunnel?token=abc"
	if got != want {
		t.Fatalf("sessionWebSocketURL() = %q, want %q", got, want)
	}
}

func TestSessionWebSocketURLCanUseRawOrigin(t *testing.T) {
	t.Setenv("TUIST_RUNNER_SHELL_USE_DISCOVERY_ORIGIN", "0")

	got, err := sessionWebSocketURL(
		runnerSession{WebSocketURL: "wss://public.example.com/tunnel"},
		"https://internal.example.com/sessions",
	)
	if err != nil {
		t.Fatal(err)
	}

	if got != "wss://public.example.com/tunnel" {
		t.Fatalf("sessionWebSocketURL() = %q", got)
	}
}

func TestPromptHostShortensRunnerName(t *testing.T) {
	t.Setenv("TUIST_RUNNER_SHELL_PROMPT_HOST", "")
	t.Setenv("TUIST_RUNNER_POD_NAME", "tuist-tuist-runner-pool-linux-2vcpu-8gb-runner-cfd7bea7")

	if got := promptHost(); got != "cfd7bea7" {
		t.Fatalf("promptHost() = %q, want cfd7bea7", got)
	}
}

func TestPromptHostSanitizesConfiguredValue(t *testing.T) {
	t.Setenv("TUIST_RUNNER_SHELL_PROMPT_HOST", "runner; rm -rf /")

	if got := promptHost(); got != "runnerrm-rf" {
		t.Fatalf("promptHost() = %q, want runnerrm-rf", got)
	}
}
