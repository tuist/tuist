package main

import (
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

// claudeCodeVersion and claudeCodeChecksums are the one source of the Claude
// Code build. The Linux template, the Claude Code orchestrator image and
// tart-kubelet's macOS tools share repeat them, because each is built
// separately; this keeps every copy on the build sbx-worker expects.
func TestClaudeCodePinsMatchSbxWorker(t *testing.T) {
	// The image build runs the tests with only this module copied in; the
	// repository checkout (CI's Test step) holds the other copies.
	if _, err := os.Stat(filepath.FromSlash("../../../AGENTS.md")); err != nil {
		t.Skip("needs the repository checkout:", err)
	}
	copies := []struct {
		path, platform, version, sha string
	}{
		{"../../Dockerfile", "linux-x64", `ARG CLAUDE_CODE_VERSION=(\S+)`, `ARG CLAUDE_CODE_SHA256=(\S+)`},
		{"../../../claude-code-runners/Dockerfile", "linux-x64", `ARG CLAUDE_CODE_VERSION=(\S+)`, `ARG CLAUDE_CODE_SHA256=(\S+)`},
		{"../../../tart-kubelet/internal/macosandbox/tools.go", "darwin-arm64", `claudeCodeVersion\s*=\s*"([^"]+)"`, `claudeCodeDarwinSHA256\s*=\s*"([^"]+)"`},
	}
	for _, c := range copies {
		data, err := os.ReadFile(filepath.FromSlash(c.path))
		if err != nil {
			t.Fatal(err)
		}
		for _, want := range []struct{ pattern, value string }{
			{c.version, claudeCodeVersion},
			{c.sha, claudeCodeChecksums[c.platform]},
		} {
			m := regexp.MustCompile(want.pattern).FindSubmatch(data)
			if m == nil {
				t.Errorf("%s: no match for %s", c.path, want.pattern)
				continue
			}
			if got := string(m[1]); got != want.value {
				t.Errorf("%s pins %s, sbx-worker expects %s", c.path, got, want.value)
			}
		}
	}
}
