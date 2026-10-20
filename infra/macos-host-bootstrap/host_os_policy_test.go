package bootstrap

import (
	"encoding/xml"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// Each stub records its argv, one call per line, arguments separated by
// \x1f so an argument that failed to split shows up as one field.
const (
	stubSudo = `#!/bin/sh
{ printf 'sudo'; for arg in "$@"; do printf '\037%s' "$arg"; done; printf '\n'; } >>"$STUB_LOG"
if [ "$1" = tee ]; then
  mkdir -p "$STUB_ROOT$(dirname "$2")"
  cat >"$STUB_ROOT$2"
fi
`
	stubDefaults = `#!/bin/sh
{ printf 'defaults'; for arg in "$@"; do printf '\037%s' "$arg"; done; printf '\n'; } >>"$STUB_LOG"
`
	stubSwVers = `#!/bin/sh
case "$1" in
  -productVersion) echo 26.3 ;;
  -buildVersion) echo 25D125 ;;
esac
`
)

// stubShells are the shells a rendered script is exercised under. zsh is the
// login shell of every fleet host, and so what RunCommand's scripts run in.
func stubShells(t *testing.T) map[string][]string {
	t.Helper()
	shells := map[string][]string{"bash": {"bash", "--noprofile", "--norc"}}
	if _, err := exec.LookPath("zsh"); err == nil {
		shells["zsh"] = []string{"zsh", "-f"}
	}
	return shells
}

// runScriptWithStubs runs script as `<shell> -c`, like RunCommand over SSH,
// with sudo, defaults and sw_vers replaced by recorders so nothing touches the
// machine running the test. It returns every recorded call and the directory
// standing in for / for files written through `sudo tee`.
func runScriptWithStubs(t *testing.T, shell []string, script string) ([][]string, string) {
	t.Helper()

	dir := t.TempDir()
	bin := filepath.Join(dir, "bin")
	root := filepath.Join(dir, "root")
	log := filepath.Join(dir, "calls")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatalf("mkdir stubs: %v", err)
	}
	for name, body := range map[string]string{"sudo": stubSudo, "defaults": stubDefaults, "sw_vers": stubSwVers} {
		if err := os.WriteFile(filepath.Join(bin, name), []byte(body), 0o755); err != nil {
			t.Fatalf("write stub %s: %v", name, err)
		}
	}

	cmd := exec.Command(shell[0], append(slices.Clone(shell[1:]), "-c", script)...)
	cmd.Env = append(os.Environ(),
		"PATH="+bin+string(os.PathListSeparator)+os.Getenv("PATH"),
		"STUB_LOG="+log,
		"STUB_ROOT="+root,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%s: script failed: %v\n%s\n---\n%s", shell[0], err, out, script)
	}

	data, err := os.ReadFile(log)
	if err != nil {
		t.Fatalf("read recorded calls: %v", err)
	}
	var calls [][]string
	for line := range strings.SplitSeq(strings.TrimSuffix(string(data), "\n"), "\n") {
		calls = append(calls, strings.Split(line, "\x1f"))
	}
	return calls, root
}

// Nothing that changes OS code or restarts the host installs on its own;
// update checks and system data files (XProtect, Gatekeeper) keep flowing.
func TestSoftwareUpdatePolicy_HoldsOSChangesForOperatorWaves(t *testing.T) {
	want := map[string]string{
		"AutomaticCheckEnabled":            "true",
		"AutomaticDownload":                "false",
		"AutomaticallyInstallMacOSUpdates": "false",
		"SplatEnabled":                     "false",
		"CriticalUpdateInstall":            "false",
		"ConfigDataInstall":                "true",
	}
	prefix := []string{"sudo", "defaults", "write", "/Library/Preferences/com.apple.SoftwareUpdate"}

	for name, shell := range stubShells(t) {
		t.Run(name, func(t *testing.T) {
			calls, _ := runScriptWithStubs(t, shell, renderSoftwareUpdatePolicyScript())

			got := map[string]string{}
			for _, call := range calls {
				if len(call) != 7 || !slices.Equal(call[:4], prefix) || call[5] != "-bool" {
					t.Fatalf("unexpected call %q: softwareupdated reads system-wide booleans from /Library/Preferences/com.apple.SoftwareUpdate", call)
				}
				got[call[4]] = call[6]
			}
			if !maps.Equal(got, want) {
				t.Fatalf("software update policy = %v, want %v", got, want)
			}
		})
	}
}

// The "Update Mac Automatically" pane opts the host into automatic macOS
// installs on Continue, and enabling FileVault turns auto-login off, which
// leaves Tart without a console session.
func TestSetupAssistantSkipItems_CoverPanesThatChangeTheHost(t *testing.T) {
	for _, item := range []string{"SoftwareUpdate", "UpdateCompleted", "FileVault"} {
		if !slices.Contains(setupAssistantSkipItems, item) {
			t.Errorf("setupAssistantSkipItems must include %q", item)
		}
	}
}

func TestSetupAssistantScript_SkipsPanesForTheAutoLoginUser(t *testing.T) {
	skip := append([]string{"SkipSetupItems", "-array"}, setupAssistantSkipItems...)
	wantCalls := [][]string{
		append([]string{"sudo", "defaults", "write", "/Library/Preferences/com.apple.SetupAssistant.managed"}, skip...),
		append([]string{"sudo", "-u", "tuist", "defaults", "write", "com.apple.SetupAssistant.managed"}, skip...),
		{"sudo", "defaults", "write", "/Library/Preferences/com.apple.SetupAssistant", "DidSeeCloudSetup", "-bool", "true"},
		{"sudo", "-u", "tuist", "defaults", "write", "com.apple.SetupAssistant", "DidSeePrivacy", "-bool", "true"},
		{"sudo", "defaults", "write", "/Library/Preferences/com.apple.SetupAssistant", "LastSeenCloudProductVersion", "-string", "26.3"},
		{"sudo", "-u", "tuist", "defaults", "write", "com.apple.SetupAssistant", "LastSeenCloudProductVersion", "-string", "26.3"},
		{"sudo", "defaults", "write", "/Library/Preferences/com.apple.SetupAssistant", "LastSeenBuddyBuildVersion", "-string", "25D125"},
		{"sudo", "-u", "tuist", "defaults", "write", "com.apple.SetupAssistant", "LastSeenBuddyBuildVersion", "-string", "25D125"},
	}

	for name, shell := range stubShells(t) {
		t.Run(name, func(t *testing.T) {
			calls, root := runScriptWithStubs(t, shell, renderSetupAssistantScript(Config{SSHUser: "tuist"}))

			for _, path := range []string{
				"/Library/Managed Preferences/com.apple.SetupAssistant.managed.plist",
				"/Library/Managed Preferences/tuist/com.apple.SetupAssistant.managed.plist",
			} {
				if got := readSkipSetupItems(t, filepath.Join(root, path)); !slices.Equal(got, setupAssistantSkipItems) {
					t.Errorf("%s SkipSetupItems = %q, want %q", path, got, setupAssistantSkipItems)
				}
			}
			for _, want := range wantCalls {
				if !slices.ContainsFunc(calls, func(call []string) bool { return slices.Equal(call, want) }) {
					t.Errorf("missing call %q", want)
				}
			}
		})
	}
}

func readSkipSetupItems(t *testing.T, path string) []string {
	t.Helper()

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if _, err := exec.LookPath("plutil"); err == nil {
		if out, err := exec.Command("plutil", "-lint", path).CombinedOutput(); err != nil {
			t.Fatalf("plutil rejects %s: %v\n%s", path, err, out)
		}
	}
	var doc struct {
		Dict struct {
			Keys  []string `xml:"key"`
			Items []string `xml:"array>string"`
		} `xml:"dict"`
	}
	if err := xml.Unmarshal(data, &doc); err != nil {
		t.Fatalf("parse %s: %v\n%s", path, err, data)
	}
	if !slices.Equal(doc.Dict.Keys, []string{"SkipSetupItems"}) {
		t.Fatalf("%s keys = %q, want only SkipSetupItems", path, doc.Dict.Keys)
	}
	return doc.Dict.Items
}
