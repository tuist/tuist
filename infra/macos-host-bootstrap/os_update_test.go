package bootstrap

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

// Captured from ber1-proto-01 on macOS 26.6 (25G72).
const softwareUpdateListTahoe266 = "Software Update Tool\n\n" +
	"Finding available software\n" +
	"Software Update found the following new or updated software:\n" +
	"* Label: Safari27.0TahoeAuto-27.0\n" +
	"\tTitle: Safari, Version: 27.0, Size: 249465KiB, Recommended: YES, \n" +
	"* Label: macOS Tahoe 26.7-25G229\n" +
	"\tTitle: macOS Tahoe 26.7, Version: 26.7, Size: 3039632KiB, Recommended: YES, Action: restart, \n" +
	"* Label: macOS 27-26A428\n" +
	"\tTitle: macOS 27, Version: 27, Size: 11727219KiB, Recommended: YES, Action: restart, \n"

func TestParseSoftwareUpdateList(t *testing.T) {
	got := ParseSoftwareUpdateList(softwareUpdateListTahoe266)
	want := []OSUpdate{
		{Label: "Safari27.0TahoeAuto-27.0", Title: "Safari", Version: "27.0"},
		{Label: "macOS Tahoe 26.7-25G229", Title: "macOS Tahoe 26.7", Version: "26.7"},
		{Label: "macOS 27-26A428", Title: "macOS 27", Version: "27"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ParseSoftwareUpdateList:\n got %#v\nwant %#v", got, want)
	}
	if got[0].IsMacOS() {
		t.Error("Safari parsed as a macOS update")
	}
	if !got[1].IsMacOS() || !got[2].IsMacOS() {
		t.Error("macOS entries not recognised as macOS updates")
	}
}

func TestParseSoftwareUpdateListWithNothingOffered(t *testing.T) {
	got := ParseSoftwareUpdateList("Software Update Tool\n\nFinding available software\nNo new software available.\n")
	if len(got) != 0 {
		t.Fatalf("expected no updates, got %#v", got)
	}
}

func TestParseKernBootTime(t *testing.T) {
	got, err := ParseKernBootTime("{ sec = 1790153387, usec = 566452 } Wed Sep 23 01:49:47 2026\n")
	if err != nil || got != 1790153387 {
		t.Fatalf("ParseKernBootTime = %d, %v", got, err)
	}
	if _, err := ParseKernBootTime("garbage"); err == nil {
		t.Fatal("expected an error for unrecognised output")
	}
}

// Output format from ber1-proto-01 on 26.6; sysadminctl writes it to stderr.
func TestParseSecureTokenStatus(t *testing.T) {
	for _, tc := range []struct {
		out  string
		want bool
	}{
		{"2026-09-23 10:10:38.619 sysadminctl[1053:11513] Secure token is ENABLED for user Tuist Runner Operator\n", true},
		{"2026-09-23 09:41:40.102 sysadminctl[1290:12512] Secure token is DISABLED for user Tuist Runner Operator\n", false},
	} {
		got, err := ParseSecureTokenStatus(tc.out)
		if err != nil || got != tc.want {
			t.Errorf("ParseSecureTokenStatus(%q) = %t, %v; want %t", tc.out, got, err, tc.want)
		}
	}
	if _, err := ParseSecureTokenStatus("2026-09-23 10:10:38.638 sysadminctl[1056:11522] Unknown user nosuchuser\n"); err == nil {
		t.Error("an unknown user must be an error, not a missing token")
	}
}

func TestParseOSUpdateJob(t *testing.T) {
	for _, tc := range []struct {
		out  string
		want OSUpdateJob
	}{
		{"absent\n", OSUpdateJob{State: OSUpdateJobAbsent}},
		{"running\nDownloading: 30.00%\n", OSUpdateJob{State: OSUpdateJobRunning, LogTail: "Downloading: 30.00%"}},
		{"exited 0\n", OSUpdateJob{State: OSUpdateJobExited}},
		{"exited 1\nError downloading updates.\n", OSUpdateJob{State: OSUpdateJobExited, ExitCode: 1, LogTail: "Error downloading updates."}},
	} {
		got, err := parseOSUpdateJob(tc.out)
		if err != nil || got != tc.want {
			t.Errorf("parseOSUpdateJob(%q) = %#v, %v; want %#v", tc.out, got, err, tc.want)
		}
	}
	if _, err := parseOSUpdateJob("mystery\n"); err == nil {
		t.Error("expected an error for an unrecognised state")
	}
}

// loginShells are the shells a host may run the scripts under: sshd runs commands through the user's login shell, which is zsh on the fleet.
func loginShells(t *testing.T) []string {
	shells := []string{"/bin/sh"}
	if zsh, err := exec.LookPath("zsh"); err == nil {
		shells = append(shells, zsh)
	}
	return shells
}

func runScript(t *testing.T, shell, script, stdin string, env ...string) {
	t.Helper()
	cmd := exec.Command(shell, "-c", script)
	cmd.Stdin = strings.NewReader(stdin)
	cmd.Env = append(os.Environ(), env...)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%s: %v\n%s", shell, err, out)
	}
}

func jobState(t *testing.T, shell, dir, job string, env ...string) OSUpdateJob {
	t.Helper()
	cmd := exec.Command(shell, "-c", renderOSUpdateJobStateScript(dir, job))
	cmd.Env = append(os.Environ(), env...)
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("job state under %s: %v", shell, err)
	}
	state, err := parseOSUpdateJob(string(out))
	if err != nil {
		t.Fatal(err)
	}
	return state
}

func waitForExit(t *testing.T, shell, dir, job string) OSUpdateJob {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if state := jobState(t, shell, dir, job); state.State == OSUpdateJobExited {
			return state
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("job %s never exited under %s", job, shell)
	return OSUpdateJob{}
}

func TestOSUpdateJobRecordsTheExitCodeOfAFailingBody(t *testing.T) {
	for _, shell := range loginShells(t) {
		dir := t.TempDir()
		runScript(t, shell, renderOSUpdateJobScript(dir, OSUpdateJobDownload, "", "sh -c 'echo Error downloading updates.; exit 3'"), "")
		got := waitForExit(t, shell, dir, OSUpdateJobDownload)
		if got.ExitCode != 3 || got.LogTail != "Error downloading updates." {
			t.Errorf("%s: got %#v", shell, got)
		}
	}
}

func TestOSUpdateJobReturnsWhileItsBodyRuns(t *testing.T) {
	for _, shell := range loginShells(t) {
		dir := t.TempDir()
		start := time.Now()
		runScript(t, shell, renderOSUpdateJobScript(dir, OSUpdateJobDownload, "", "sleep 1"), "")
		if elapsed := time.Since(start); elapsed >= time.Second {
			t.Errorf("%s: starting the job waited %s for its body", shell, elapsed)
		}
		if got := jobState(t, shell, dir, OSUpdateJobDownload); got.State != OSUpdateJobRunning {
			t.Errorf("%s: state right after start = %#v, want running", shell, got)
		}
		if got := waitForExit(t, shell, dir, OSUpdateJobDownload); got.ExitCode != 0 {
			t.Errorf("%s: got %#v", shell, got)
		}
	}
}

func TestOSUpdateJobStateIsAbsentBeforeAnyJob(t *testing.T) {
	for _, shell := range loginShells(t) {
		if got := jobState(t, shell, t.TempDir(), OSUpdateJobInstall); got.State != OSUpdateJobAbsent {
			t.Errorf("%s: got %#v", shell, got)
		}
	}
}

func TestOSUpdateInstallPassesThePasswordOnStdinOnly(t *testing.T) {
	const password = "s3cr3t-volume-owner"
	for _, shell := range loginShells(t) {
		dir := t.TempDir()
		bin := t.TempDir()
		argv := filepath.Join(bin, "argv")
		stdin := filepath.Join(bin, "stdin")
		fakeSudo := "#!/bin/sh\nprintf '%s\\n' \"$*\" > \"$FAKE_SUDO_ARGV\"\ncat > \"$FAKE_SUDO_STDIN\"\n"
		if err := os.WriteFile(filepath.Join(bin, "sudo"), []byte(fakeSudo), 0o755); err != nil {
			t.Fatal(err)
		}
		env := []string{
			"PATH=" + bin + ":" + os.Getenv("PATH"),
			"FAKE_SUDO_ARGV=" + argv,
			"FAKE_SUDO_STDIN=" + stdin,
		}

		script := renderOSUpdateInstallScript(dir, "macOS Tahoe 26.7-25G229", "tuist")
		runScript(t, shell, script, password+"\n", env...)
		if got := waitForExit(t, shell, dir, OSUpdateJobInstall); got.ExitCode != 0 {
			t.Fatalf("%s: install job %#v", shell, got)
		}

		gotArgv, _ := os.ReadFile(argv)
		gotStdin, _ := os.ReadFile(stdin)
		if want := "-n softwareupdate --install macOS Tahoe 26.7-25G229 --restart --user tuist --stdinpass\n"; string(gotArgv) != want {
			t.Errorf("%s: sudo argv = %q, want %q", shell, gotArgv, want)
		}
		if strings.Contains(string(gotArgv), password) || strings.Contains(script, password) {
			t.Errorf("%s: the password reached a command line", shell)
		}
		if string(gotStdin) != password+"\n" {
			t.Errorf("%s: softwareupdate stdin = %q, want the password", shell, gotStdin)
		}
	}
}
