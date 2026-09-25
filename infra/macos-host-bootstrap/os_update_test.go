package bootstrap

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strconv"
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
		{"lost\nRestarting...\n", OSUpdateJob{State: OSUpdateJobLost, LogTail: "Restarting..."}},
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

func jobState(t *testing.T, shell, root, id, job string, env ...string) OSUpdateJob {
	t.Helper()
	cmd := exec.Command(shell, "-c", renderOSUpdateJobStateScript(root, id, job))
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

func waitForExit(t *testing.T, shell, root, id, job string) OSUpdateJob {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if state := jobState(t, shell, root, id, job); state.State == OSUpdateJobExited {
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
		runScript(t, shell, renderOSUpdateJobScript(dir, "u1", OSUpdateJobDownload, "", "sh -c 'echo Error downloading updates.; exit 3'"), "")
		got := waitForExit(t, shell, dir, "u1", OSUpdateJobDownload)
		if got.ExitCode != 3 || got.LogTail != "Error downloading updates." {
			t.Errorf("%s: got %#v", shell, got)
		}
	}
}

func TestOSUpdateJobReturnsWhileItsBodyRuns(t *testing.T) {
	for _, shell := range loginShells(t) {
		dir := t.TempDir()
		start := time.Now()
		runScript(t, shell, renderOSUpdateJobScript(dir, "u1", OSUpdateJobDownload, "", "sleep 1"), "")
		if elapsed := time.Since(start); elapsed >= time.Second {
			t.Errorf("%s: starting the job waited %s for its body", shell, elapsed)
		}
		if got := jobState(t, shell, dir, "u1", OSUpdateJobDownload); got.State != OSUpdateJobRunning {
			t.Errorf("%s: state right after start = %#v, want running", shell, got)
		}
		if got := waitForExit(t, shell, dir, "u1", OSUpdateJobDownload); got.ExitCode != 0 {
			t.Errorf("%s: got %#v", shell, got)
		}
	}
}

func TestOSUpdateJobStateIsAbsentBeforeAnyJob(t *testing.T) {
	for _, shell := range loginShells(t) {
		if got := jobState(t, shell, t.TempDir(), "u1", OSUpdateJobInstall); got.State != OSUpdateJobAbsent {
			t.Errorf("%s: got %#v", shell, got)
		}
	}
}

func TestOSUpdateJobWhoseProcessDiedWithoutAnExitCodeIsLost(t *testing.T) {
	for _, shell := range loginShells(t) {
		root := t.TempDir()
		dir := filepath.Join(root, "u1")
		if err := os.MkdirAll(dir, 0o700); err != nil {
			t.Fatal(err)
		}
		dead := exec.Command("true")
		if err := dead.Run(); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, OSUpdateJobInstall+".pid"), []byte(strconv.Itoa(dead.Process.Pid)+"\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		if got := jobState(t, shell, root, "u1", OSUpdateJobInstall); got.State != OSUpdateJobLost {
			t.Errorf("%s: got %#v, want lost", shell, got)
		}
	}
}

func TestOSUpdateJobBelongsToItsUpdate(t *testing.T) {
	for _, shell := range loginShells(t) {
		root := t.TempDir()
		runScript(t, shell, renderOSUpdateJobScript(root, "earlier", OSUpdateJobDownload, "", "true"), "")
		waitForExit(t, shell, root, "earlier", OSUpdateJobDownload)
		if err := os.WriteFile(filepath.Join(root, OSUpdateJobInstall+".exit"), []byte("0\n"), 0o600); err != nil {
			t.Fatal(err)
		}

		if got := jobState(t, shell, root, "later", OSUpdateJobDownload); got.State != OSUpdateJobAbsent {
			t.Errorf("%s: another update's download reads as %#v, want absent", shell, got)
		}
		runScript(t, shell, renderOSUpdateJobScript(root, "later", OSUpdateJobDownload, "", "true"), "")
		waitForExit(t, shell, root, "later", OSUpdateJobDownload)
		entries, err := os.ReadDir(root)
		if err != nil {
			t.Fatal(err)
		}
		if len(entries) != 1 || entries[0].Name() != "later" {
			t.Errorf("%s: after the later update started a job, the root holds %v, want only its directory", shell, entries)
		}
	}
}

func TestOSUpdateSessionRejectsAnIDThatIsNotAPathSegment(t *testing.T) {
	for _, id := range []string{"", "../etc", "a b", "a/b"} {
		if err := checkOSUpdateID(id); err == nil {
			t.Errorf("checkOSUpdateID(%q) accepted it", id)
		}
	}
	if err := checkOSUpdateID("0b8f2c1e-5d3a-4c55-9a7e-2f1d6b9c4e10"); err != nil {
		t.Errorf("rejected a UUID: %v", err)
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

		script := renderOSUpdateInstallScript(dir, "u1", "macOS Tahoe 26.7-25G229", "tuist")
		runScript(t, shell, script, password+"\n", env...)
		if got := waitForExit(t, shell, dir, "u1", OSUpdateJobInstall); got.ExitCode != 0 {
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

// Captured from ber1-proto-01 on macOS 27.0 (26A428).
const fullInstallerListGoldenGate = "Finding available software\n" +
	"Software Update found the following full installers:\n" +
	"* Title: macOS 27 Golden Gate, Version: 27.0, Size: 17969056KiB, Build: 26A428, Deferred: NO\n" +
	"* Title: macOS Tahoe, Version: 26.7, Size: 17951133KiB, Build: 25G229, Deferred: NO\n" +
	"* Title: macOS Tahoe, Version: 26.6.2, Size: 17953734KiB, Build: 25G83, Deferred: NO\n" +
	"* Title: macOS Sequoia, Version: 15.8, Size: 15296950KiB, Build: 24H23, Deferred: NO\n"

func TestParseFullInstallerList(t *testing.T) {
	got := ParseFullInstallerList(fullInstallerListGoldenGate)
	want := []OSInstaller{
		{Title: "macOS 27 Golden Gate", Version: "27.0", Build: "26A428"},
		{Title: "macOS Tahoe", Version: "26.7", Build: "25G229"},
		{Title: "macOS Tahoe", Version: "26.6.2", Build: "25G83"},
		{Title: "macOS Sequoia", Version: "15.8", Build: "24H23"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ParseFullInstallerList:\n got %#v\nwant %#v", got, want)
	}
	if app := got[0].App(); app != "/Applications/Install macOS 27 Golden Gate.app" {
		t.Errorf("App() = %q", app)
	}
}

func TestParseIORegSerial(t *testing.T) {
	got, err := ParseIORegSerial("+-o Macmini9,1  <class IOPlatformExpertDevice>\n    {\n      \"IOPlatformSerialNumber\" = \"C07FC05JQ6NY\"\n    }\n")
	if err != nil || got != "C07FC05JQ6NY" {
		t.Fatalf("ParseIORegSerial = %q, %v", got, err)
	}
	if _, err := ParseIORegSerial("nothing here"); err == nil {
		t.Error("expected an error without a serial")
	}
}

// fakeSudo installs a sudo that records its argv and stdin, and returns the environment that puts it first on PATH.
func fakeSudo(t *testing.T) (env []string, argv, stdin string) {
	t.Helper()
	bin := t.TempDir()
	argv = filepath.Join(bin, "argv")
	stdin = filepath.Join(bin, "stdin")
	script := "#!/bin/sh\nprintf '%s\\n' \"$*\" > \"$FAKE_SUDO_ARGV\"\ncat > \"$FAKE_SUDO_STDIN\"\n"
	if err := os.WriteFile(filepath.Join(bin, "sudo"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return []string{"PATH=" + bin + ":" + os.Getenv("PATH"), "FAKE_SUDO_ARGV=" + argv, "FAKE_SUDO_STDIN=" + stdin}, argv, stdin
}

// passthroughSudo installs a sudo that runs its command as the current user.
func passthroughSudo(t *testing.T) []string {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "sudo"), []byte("#!/bin/sh\n[ \"$1\" = -n ] && shift\nexec \"$@\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	return []string{"PATH=" + bin + ":" + os.Getenv("PATH")}
}

func TestOSUpdateEraseReadsThePasswordFromStdinOnly(t *testing.T) {
	const password = "s3cr3t-volume-owner"
	installer := OSInstaller{Title: "macOS 27 Golden Gate", Version: "27.0", Build: "26A428"}
	for _, shell := range loginShells(t) {
		root := t.TempDir()
		env, argv, stdin := fakeSudo(t)
		script := renderOSUpdateEraseScript(root, "u1", installer, "tuist")
		runScript(t, shell, script, password+"\n", env...)
		if got := waitForExit(t, shell, root, "u1", OSUpdateJobErase); got.ExitCode != 0 {
			t.Fatalf("%s: erase job %#v", shell, got)
		}
		gotArgv, _ := os.ReadFile(argv)
		gotStdin, _ := os.ReadFile(stdin)
		want := "-n /Applications/Install macOS 27 Golden Gate.app/Contents/Resources/startosinstall --eraseinstall --agreetolicense --forcequitapps --newvolumename Macintosh HD --user tuist --stdinpass\n"
		if string(gotArgv) != want {
			t.Errorf("%s: sudo argv = %q, want %q", shell, gotArgv, want)
		}
		if strings.Contains(string(gotArgv), password) || strings.Contains(script, password) {
			t.Errorf("%s: the password reached a command line", shell)
		}
		if string(gotStdin) != password+"\n" {
			t.Errorf("%s: startosinstall stdin = %q, want the password", shell, gotStdin)
		}
	}
}

func TestOSUpdateFetchesTheFullInstallerForTheTarget(t *testing.T) {
	for _, shell := range loginShells(t) {
		root := t.TempDir()
		env, argv, _ := fakeSudo(t)
		runScript(t, shell, renderOSUpdateFetchInstallerScript(root, "u1", "27.0"), "", env...)
		waitForExit(t, shell, root, "u1", OSUpdateJobDownload)
		gotArgv, _ := os.ReadFile(argv)
		if want := "-n softwareupdate --fetch-full-installer --full-installer-version 27.0\n"; string(gotArgv) != want {
			t.Errorf("%s: sudo argv = %q, want %q", shell, gotArgv, want)
		}
	}
}

func TestTailscaleStateRestoresOnlyOnAHostWithoutOne(t *testing.T) {
	for _, shell := range loginShells(t) {
		env := passthroughSudo(t)
		path := filepath.Join(t.TempDir(), "lib", "tailscale", "tailscaled.state")
		runScript(t, shell, renderTailscaleStateRestoreScript(path), `{"_machinekey":"old"}`, env...)
		got, err := os.ReadFile(path)
		if err != nil || string(got) != `{"_machinekey":"old"}` {
			t.Fatalf("%s: restored %q, %v", shell, got, err)
		}
		if info, _ := os.Stat(path); info.Mode().Perm() != 0o600 {
			t.Errorf("%s: state mode %v, want 0600", shell, info.Mode().Perm())
		}

		runScript(t, shell, renderTailscaleStateRestoreScript(path), `{"_machinekey":"other"}`, env...)
		if got, _ := os.ReadFile(path); string(got) != `{"_machinekey":"old"}` {
			t.Errorf("%s: overwrote the state of a host already on the tailnet: %q", shell, got)
		}
	}
}

func TestTailscaleStateReadIsEmptyWithoutAState(t *testing.T) {
	for _, shell := range loginShells(t) {
		env := passthroughSudo(t)
		path := filepath.Join(t.TempDir(), "tailscaled.state")
		read := func() string {
			cmd := exec.Command(shell, "-c", renderTailscaleStateReadScript(path))
			cmd.Env = append(os.Environ(), env...)
			out, err := cmd.Output()
			if err != nil {
				t.Fatalf("%s: %v", shell, err)
			}
			return string(out)
		}
		if got := read(); got != "" {
			t.Errorf("%s: read %q from a host without a state", shell, got)
		}
		if err := os.WriteFile(path, []byte(`{"_machinekey":"k"}`), 0o600); err != nil {
			t.Fatal(err)
		}
		if got := read(); got != `{"_machinekey":"k"}` {
			t.Errorf("%s: read %q", shell, got)
		}
	}
}
