package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestConfigValidate_ReportsAllMissing(t *testing.T) {
	cfg := Config{}
	err := cfg.validate()
	if err == nil {
		t.Fatalf("expected error for empty config")
	}
	for _, name := range []string{"IP", "SSHUser", "Hostname", "GHRepo", "GHToken"} {
		if !strings.Contains(err.Error(), name) {
			t.Errorf("expected error to mention %s, got: %v", name, err)
		}
	}
}

func TestConfigValidate_AcceptsKeyBytes(t *testing.T) {
	cfg := Config{
		IP:            "1.2.3.4",
		SSHUser:       "m1",
		SSHPrivateKey: []byte("dummy"),
		Hostname:      "vm-image-builder-2",
		GHRepo:        "tuist/tuist",
		GHToken:       "AAAAA",
	}
	if err := cfg.validate(); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestConfigValidate_AcceptsSSHAgent(t *testing.T) {
	cfg := Config{
		IP:          "1.2.3.4",
		SSHUser:     "m1",
		UseSSHAgent: true,
		Hostname:    "vm-image-builder-2",
		GHRepo:      "tuist/tuist",
		GHToken:     "AAAAA",
	}
	if err := cfg.validate(); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestConfigValidate_RejectsBothAuthMethods(t *testing.T) {
	cfg := Config{
		IP:            "1.2.3.4",
		SSHUser:       "m1",
		SSHPrivateKey: []byte("dummy"),
		UseSSHAgent:   true,
		Hostname:      "vm-image-builder-2",
		GHRepo:        "tuist/tuist",
		GHToken:       "AAAAA",
	}
	err := cfg.validate()
	if err == nil || !strings.Contains(err.Error(), "mutually exclusive") {
		t.Fatalf("expected mutually-exclusive error, got: %v", err)
	}
}

func TestConfigValidate_RejectsNoAuthMethod(t *testing.T) {
	cfg := Config{
		IP:       "1.2.3.4",
		SSHUser:  "m1",
		Hostname: "vm-image-builder-2",
		GHRepo:   "tuist/tuist",
		GHToken:  "AAAAA",
	}
	err := cfg.validate()
	if err == nil || !strings.Contains(err.Error(), "is required") {
		t.Fatalf("expected required-auth error, got: %v", err)
	}
}

func TestApplyDefaults_FillsMissing(t *testing.T) {
	cfg := Config{Hostname: "vm-image-builder-2"}
	cfg.applyDefaults()
	if cfg.RunnerName != "vm-image-builder-2" {
		t.Errorf("RunnerName: want vm-image-builder-2, got %q", cfg.RunnerName)
	}
	if cfg.RunnerLabels != DefaultRunnerLabels {
		t.Errorf("RunnerLabels: want %q, got %q", DefaultRunnerLabels, cfg.RunnerLabels)
	}
	if cfg.RunnerVersion != DefaultRunnerVersion {
		t.Errorf("RunnerVersion: want %q, got %q", DefaultRunnerVersion, cfg.RunnerVersion)
	}
	if cfg.TuistMixBuildRoot != DefaultTuistMixBuildRoot {
		t.Errorf("TuistMixBuildRoot: want %q, got %q", DefaultTuistMixBuildRoot, cfg.TuistMixBuildRoot)
	}
}

func TestApplyDefaults_PreservesNonEmpty(t *testing.T) {
	cfg := Config{
		Hostname:          "vm-image-builder-3",
		RunnerName:        "custom-name",
		RunnerLabels:      "self-hosted,macos,custom",
		RunnerVersion:     "2.999.0",
		TuistMixBuildRoot: "/tmp/cache",
	}
	cfg.applyDefaults()
	if cfg.RunnerName != "custom-name" {
		t.Errorf("RunnerName clobbered: got %q", cfg.RunnerName)
	}
	if cfg.RunnerLabels != "self-hosted,macos,custom" {
		t.Errorf("RunnerLabels clobbered: got %q", cfg.RunnerLabels)
	}
	if cfg.RunnerVersion != "2.999.0" {
		t.Errorf("RunnerVersion clobbered: got %q", cfg.RunnerVersion)
	}
	if cfg.TuistMixBuildRoot != "/tmp/cache" {
		t.Errorf("TuistMixBuildRoot clobbered: got %q", cfg.TuistMixBuildRoot)
	}
}

// The DefaultRunnerLabels constant is what the host advertises to
// GitHub; drift between it and the workflow `runs-on` selector makes
// the host invisible to the scheduler. Pin the literal here so a
// change to the constant trips the test before it ships.
func TestDefaultRunnerLabelsMatchWorkflowSelector(t *testing.T) {
	want := "self-hosted,macos,bare-metal,vm-image-builder"
	if DefaultRunnerLabels != want {
		t.Fatalf("DefaultRunnerLabels = %q; workflows pin runs-on: [%s]", DefaultRunnerLabels, strings.ReplaceAll(want, ",", ", "))
	}
}

func TestPrefixWriter_TagsCompleteLines(t *testing.T) {
	var buf bytes.Buffer
	pw := &prefixWriter{w: &buf, prefix: []byte("[step] ")}
	pw.Write([]byte("first line\nsecond"))
	pw.Write([]byte(" line\n"))
	got := buf.String()
	want := "[step] first line\n[step] second line\n"
	if got != want {
		t.Errorf("prefixWriter:\n  want: %q\n  got:  %q", want, got)
	}
}

func TestShellQuote_EscapesSingleQuotes(t *testing.T) {
	got := shellQuote("foo'bar")
	want := `'foo'\''bar'`
	if got != want {
		t.Errorf("shellQuote: want %q, got %q", want, got)
	}
}

func TestTailLines_ReturnsLastN(t *testing.T) {
	in := "a\nb\nc\nd\ne\n"
	got := tailLines(in, 3)
	want := "c\nd\ne"
	if got != want {
		t.Errorf("tailLines: want %q, got %q", want, got)
	}
}

func TestTailLines_ShorterThanN(t *testing.T) {
	got := tailLines("a\nb\n", 5)
	want := "a\nb"
	if got != want {
		t.Errorf("tailLines: want %q, got %q", want, got)
	}
}
