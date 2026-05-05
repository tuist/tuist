package tart

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestStageEnvFile(t *testing.T) {
	dir := t.TempDir()
	c := &Client{UserDataDir: dir}

	staged, err := c.StageEnvFile("vm-1", map[string]string{
		"DATABASE_URL": "postgres://u:p@h/db",
		"WITH_NEWLINE": "line1\nline2",
	})
	if err != nil {
		t.Fatal(err)
	}
	if staged != filepath.Join(dir, "vm-1") {
		t.Fatalf("staged = %q", staged)
	}

	body, err := os.ReadFile(filepath.Join(staged, "tuist.env"))
	if err != nil {
		t.Fatal(err)
	}
	got := string(body)

	if !strings.Contains(got, "DATABASE_URL=postgres://u:p@h/db\n") {
		t.Errorf("missing DATABASE_URL line: %q", got)
	}
	// Newlines in values must be escaped so the file stays parseable.
	if !strings.Contains(got, `WITH_NEWLINE=line1\nline2`+"\n") {
		t.Errorf("newline not escaped: %q", got)
	}
}

func TestCleanupVMUserData(t *testing.T) {
	dir := t.TempDir()
	c := &Client{UserDataDir: dir}

	target := filepath.Join(dir, "vm-1")
	if err := os.MkdirAll(target, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := c.CleanupVMUserData("vm-1"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Fatalf("expected target removed, got err=%v", err)
	}
}

func TestShellEscape(t *testing.T) {
	cases := map[string]string{
		"simple":      `'simple'`,
		"with space":  `'with space'`,
		`with 'quote`: `'with '\''quote'`,
	}
	for in, want := range cases {
		if got := shellEscape(in); got != want {
			t.Errorf("shellEscape(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestEscapeEnvValue(t *testing.T) {
	if got := escapeEnvValue("a\nb\rc"); got != `a\nb\rc` {
		t.Fatalf("got %q", got)
	}
}
