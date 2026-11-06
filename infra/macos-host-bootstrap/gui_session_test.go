package bootstrap

import (
	"context"
	"errors"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// fakeGUISessionHost answers probes from a script of states: before the
// restart it reports preRestart, after it each probe consumes postRestart
// until one state is left, which then repeats.
type fakeGUISessionHost struct {
	preRestart  GUISessionState
	postRestart []GUISessionState
	afterKick   *GUISessionState

	restarts   int
	kicks      int
	restartErr error
}

func (f *fakeGUISessionHost) probeGUISession(context.Context) (GUISessionState, error) {
	if f.kicks > 0 && f.afterKick != nil {
		return *f.afterKick, nil
	}
	if f.restarts == 0 {
		return f.preRestart, nil
	}
	state := f.postRestart[0]
	if len(f.postRestart) > 1 {
		f.postRestart = f.postRestart[1:]
	}
	return state, nil
}

func (f *fakeGUISessionHost) kickLoginwindow(context.Context) error {
	f.kicks++
	return nil
}

func (f *fakeGUISessionHost) restart(context.Context) error {
	if f.restartErr != nil {
		return f.restartErr
	}
	f.restarts++
	return nil
}

var testGUISessionWait = guiSessionWait{
	afterRestart: 50 * time.Millisecond,
	afterKick:    50 * time.Millisecond,
	interval:     time.Millisecond,
}

var (
	setupAssistantConsole = GUISessionState{ConsoleUser: "_mbsetupuser", FileVaultOff: true}
	tuistSession          = GUISessionState{ConsoleUser: "tuist", Aqua: true, FileVaultOff: true}
)

func TestEnsureGUISession_LeavesAHostWithTheSessionAlone(t *testing.T) {
	host := &fakeGUISessionHost{preRestart: tuistSession}

	if err := ensureGUISession(context.Background(), host, "tuist", testGUISessionWait); err != nil {
		t.Fatalf("ensureGUISession: %v", err)
	}
	if host.restarts != 0 || host.kicks != 0 {
		t.Fatalf("restarted %d and kicked %d times a host that had the session", host.restarts, host.kicks)
	}
}

// The state ber1-runner-b04..b07 bootstrapped into on 2026-10-14: Setup
// Assistant's first-boot session on the console, auto-login configured behind
// it, and a restart as the only recovery.
func TestEnsureGUISession_RestartsAHostWhoseConsoleSetupAssistantHolds(t *testing.T) {
	host := &fakeGUISessionHost{
		preRestart:  setupAssistantConsole,
		postRestart: []GUISessionState{{ConsoleUser: "root", FileVaultOff: true}, tuistSession},
	}

	if err := ensureGUISession(context.Background(), host, "tuist", testGUISessionWait); err != nil {
		t.Fatalf("ensureGUISession: %v", err)
	}
	if host.restarts != 1 {
		t.Fatalf("restarts = %d, want 1", host.restarts)
	}
	if host.kicks != 0 {
		t.Fatalf("kicked loginwindow %d times although the restart brought the session up", host.kicks)
	}
}

// An Aqua domain is not enough on its own: the console has to be the user's.
func TestEnsureGUISession_RequiresTheConsoleToBeTheUsers(t *testing.T) {
	host := &fakeGUISessionHost{
		preRestart:  GUISessionState{ConsoleUser: "_mbsetupuser", Aqua: true, FileVaultOff: true},
		postRestart: []GUISessionState{tuistSession},
	}

	if err := ensureGUISession(context.Background(), host, "tuist", testGUISessionWait); err != nil {
		t.Fatalf("ensureGUISession: %v", err)
	}
	if host.restarts != 1 {
		t.Fatalf("restarts = %d, want 1", host.restarts)
	}
}

func TestEnsureGUISession_KicksLoginwindowWhenTheRestartIsNotEnough(t *testing.T) {
	host := &fakeGUISessionHost{
		preRestart:  setupAssistantConsole,
		postRestart: []GUISessionState{{ConsoleUser: "root", FileVaultOff: true}},
		afterKick:   &tuistSession,
	}

	if err := ensureGUISession(context.Background(), host, "tuist", testGUISessionWait); err != nil {
		t.Fatalf("ensureGUISession: %v", err)
	}
	if host.restarts != 1 || host.kicks != 1 {
		t.Fatalf("restarts = %d, kicks = %d, want 1 and 1", host.restarts, host.kicks)
	}
}

func TestEnsureGUISession_FailsWithoutRestartingAgain(t *testing.T) {
	stuck := GUISessionState{ConsoleUser: "root", FileVaultOff: true}
	host := &fakeGUISessionHost{
		preRestart:  setupAssistantConsole,
		postRestart: []GUISessionState{stuck},
		afterKick:   &stuck,
	}

	err := ensureGUISession(context.Background(), host, "tuist", testGUISessionWait)
	if !IsGUISessionError(err) {
		t.Fatalf("err = %v, want a GUISessionError", err)
	}
	if !IsGUISessionError(fmt.Errorf("gui session: %w", err)) {
		t.Fatal("IsGUISessionError does not see through wrapping")
	}
	if host.restarts != 1 {
		t.Fatalf("restarts = %d, want exactly 1", host.restarts)
	}
	if !strings.Contains(err.Error(), "console held by root") {
		t.Fatalf("error %q does not say who holds the console", err)
	}
	if RestartUnsafe(err) {
		t.Fatal("a host that already survived a restart is marked unsafe to restart")
	}
}

// A restart with FileVault on stops at the unlock screen, where there is no
// sshd to come back to, and auto-login could not work there anyway.
func TestEnsureGUISession_DoesNotRestartWithFileVaultOn(t *testing.T) {
	host := &fakeGUISessionHost{preRestart: GUISessionState{ConsoleUser: "root"}}

	err := ensureGUISession(context.Background(), host, "tuist", testGUISessionWait)
	if !IsGUISessionError(err) {
		t.Fatalf("err = %v, want a GUISessionError", err)
	}
	if !strings.Contains(err.Error(), "FileVault") {
		t.Fatalf("error %q does not name FileVault", err)
	}
	if host.restarts != 0 {
		t.Fatalf("restarted a FileVault host %d times", host.restarts)
	}
	if !RestartUnsafe(fmt.Errorf("gui session: %w", err)) {
		t.Fatal("a FileVault failure is not marked unsafe to restart, so controller recovery would reboot it")
	}
}

func TestEnsureGUISession_SurfacesARestartFailure(t *testing.T) {
	host := &fakeGUISessionHost{
		preRestart: setupAssistantConsole,
		restartErr: errors.New("host did not come back on a new boot within 10m0s"),
	}

	err := ensureGUISession(context.Background(), host, "tuist", testGUISessionWait)
	if err == nil || !strings.Contains(err.Error(), "did not come back") {
		t.Fatalf("err = %v, want the restart failure", err)
	}
	if !strings.Contains(err.Error(), "_mbsetupuser (Setup Assistant's first-boot session)") {
		t.Fatalf("error %q does not say what state the host was restarted from", err)
	}
}

func TestParseGUISessionProbe(t *testing.T) {
	for _, tc := range []struct {
		name string
		out  string
		want GUISessionState
	}{
		{
			name: "setup assistant holds the console",
			out:  "console=_mbsetupuser\naqua=0\nfilevault=FileVault is Off.\n",
			want: GUISessionState{ConsoleUser: "_mbsetupuser", FileVaultOff: true},
		},
		{
			name: "auto-login session up",
			out:  "console=tuist\naqua=1\nfilevault=FileVault is Off.\n",
			want: tuistSession,
		},
		{
			name: "filevault on",
			out:  "console=root\naqua=0\nfilevault=FileVault is On.\n",
			want: GUISessionState{ConsoleUser: "root"},
		},
		{
			name: "fdesetup printed nothing",
			out:  "console=root\naqua=0\nfilevault=\n",
			want: GUISessionState{ConsoleUser: "root"},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parseGUISessionProbe(tc.out)
			if err != nil {
				t.Fatalf("parse: %v", err)
			}
			if got != tc.want {
				t.Fatalf("got %+v, want %+v", got, tc.want)
			}
		})
	}
}

func TestParseGUISessionProbe_RejectsTruncatedOutput(t *testing.T) {
	if _, err := parseGUISessionProbe("console=tuist\n"); err == nil {
		t.Fatal("parsed a probe that printed neither aqua nor filevault")
	}
}

func TestRenderGUISessionProbeScript_IsValidShWithoutDeveloperTools(t *testing.T) {
	script := renderGUISessionProbeScript("tuist")
	for _, want := range []string{
		"stat -f %Su /dev/console",
		`launchctl print "gui/$uid"`,
		"session = Aqua",
		"fdesetup status",
	} {
		if !strings.Contains(script, want) {
			t.Errorf("probe script does not contain %q:\n%s", want, script)
		}
	}
	// pipefail would turn launchctl's SIGPIPE, when grep -q exits on its
	// match, into a reported missing session.
	if strings.Contains(script, "pipefail") {
		t.Error("probe script sets pipefail")
	}
	for _, forbidden := range []string{"python3", "xcrun", "xcode-select"} {
		if strings.Contains(script, forbidden) {
			t.Errorf("probe script runs %q, which a rack host does not have", forbidden)
		}
	}
	if out, err := exec.Command("sh", "-n", "-c", script).CombinedOutput(); err != nil {
		t.Fatalf("sh -n: %v\n%s", err, out)
	}
}

// Run must check the session before installing anything that makes the host
// look like a working Node, and after the steps the session depends on.
func TestRun_EnsuresGUISessionBetweenAutoLoginAndTheNodeAgent(t *testing.T) {
	order := callOrder(t, "Run")
	at := func(name string) int {
		i, ok := order[name]
		if !ok {
			t.Fatalf("Run does not call %s", name)
		}
		return i
	}
	gui := at("ensureGUISession")
	for _, before := range []string{"EnableAutoLogin", "installSetupAssistantSuppression"} {
		if at(before) > gui {
			t.Errorf("%s runs after ensureGUISession", before)
		}
	}
	for _, after := range []string{"installTart", "installTartKubelet", "loadTartKubeletLaunchd"} {
		if at(after) < gui {
			t.Errorf("%s runs before ensureGUISession", after)
		}
	}
}

// callOrder maps each function called directly in the named function of
// bootstrap.go to the source offset of its first call.
func callOrder(t *testing.T, name string) map[string]int {
	t.Helper()

	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "bootstrap.go", nil, 0)
	if err != nil {
		t.Fatalf("parse bootstrap.go: %v", err)
	}
	order := map[string]int{}
	ast.Inspect(findFunc(t, file, name), func(n ast.Node) bool {
		if call, ok := n.(*ast.CallExpr); ok {
			if ident, ok := call.Fun.(*ast.Ident); ok {
				if _, seen := order[ident.Name]; !seen {
					order[ident.Name] = int(call.Pos())
				}
			}
		}
		return true
	})
	return order
}
