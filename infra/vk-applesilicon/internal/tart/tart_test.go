package tart

import "testing"

func TestShellEscape(t *testing.T) {
	cases := map[string]string{
		"foo":     `'foo'`,
		"a b":     `'a b'`,
		"it's ok": `'it'\''s ok'`,
		"":        `''`,
		"--cpu":   `'--cpu'`,
	}
	for in, want := range cases {
		got := shellEscape(in)
		if got != want {
			t.Errorf("shellEscape(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestCommandLineUsesTartBinaryWhenSubcommandRelative(t *testing.T) {
	got := commandLine([]string{"pull", "ghcr.io/tuist/foo:bar"}, "/opt/homebrew/bin/tart")
	want := `/opt/homebrew/bin/tart 'pull' 'ghcr.io/tuist/foo:bar'`
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestCommandLinePassesAbsolutePathUnchanged(t *testing.T) {
	got := commandLine([]string{"/bin/sh", "-c", "echo hi"}, "/opt/homebrew/bin/tart")
	want := `'/bin/sh' '-c' 'echo hi'`
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}
