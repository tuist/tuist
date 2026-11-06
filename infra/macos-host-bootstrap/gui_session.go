package bootstrap

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
)

// setupAssistantUser is the account Setup Assistant runs as on a Mac's first
// boot. An ADE-enrolled host that was never rebooted after enrolment keeps it
// on the console: loginwindow does not replace its session when kicked, and
// the auto-login configured after it started only applies on the next boot.
const setupAssistantUser = "_mbsetupuser"

// GUISessionState is what a host reports about its console.
type GUISessionState struct {
	// ConsoleUser owns /dev/console: the auto-login user once its session is
	// up, root at the login window, _mbsetupuser while Setup Assistant holds it.
	ConsoleUser string
	// Aqua is whether `launchctl print gui/<uid>` reports `session = Aqua` for
	// the auto-login user.
	Aqua bool
	// FileVaultOff is whether `fdesetup status` reports FileVault off. macOS
	// disables auto-login with FileVault on, and a restart then stops at the
	// unlock screen with no sshd to come back to.
	FileVaultOff bool
}

// readyFor reports whether user holds a GUI session that Virtualization.framework
// accepts. Both halves are checked: the Aqua domain says the session exists,
// the console owner says it is the one on the display.
func (s GUISessionState) readyFor(user string) bool {
	return s.Aqua && s.ConsoleUser == user
}

func (s GUISessionState) describe() string {
	aqua := "no Aqua session"
	if s.Aqua {
		aqua = "an Aqua session"
	}
	console := s.ConsoleUser
	switch console {
	case "":
		console = "nobody"
	case setupAssistantUser:
		console += " (Setup Assistant's first-boot session)"
	}
	return fmt.Sprintf("console held by %s, %s", console, aqua)
}

// GUISessionError is a host that ended bootstrap without a GUI session for the
// auto-login user. Such a host registers a Node but cannot start a single VM.
type GUISessionError struct {
	User   string
	State  GUISessionState
	Reason string
	// RestartUnsafe is a host that a restart would leave at the FileVault
	// unlock screen with no sshd. Whatever recovers it must not reboot it.
	RestartUnsafe bool
}

func (e *GUISessionError) Error() string {
	msg := fmt.Sprintf("no GUI session for %s (%s)", e.User, e.State.describe())
	if e.Reason != "" {
		msg += ": " + e.Reason
	}
	return msg
}

// RestartUnsafe reports whether err is, or wraps, a GUISessionError for a host
// that must not be rebooted, by bootstrap or by a controller's recovery.
func RestartUnsafe(err error) bool {
	var guiErr *GUISessionError
	return errors.As(err, &guiErr) && guiErr.RestartUnsafe
}

// IsGUISessionError reports whether err is, or wraps, a GUISessionError.
func IsGUISessionError(err error) bool {
	var guiErr *GUISessionError
	return errors.As(err, &guiErr)
}

// guiSessionHost is the host side of ensureGUISession, behind an interface so
// the decision is testable without SSH.
type guiSessionHost interface {
	probeGUISession(ctx context.Context) (GUISessionState, error)
	kickLoginwindow(ctx context.Context) error
	// restart reboots the host and returns once it answers SSH on a new boot.
	restart(ctx context.Context) error
}

type guiSessionWait struct {
	// afterRestart is how long auto-login gets to raise the session once sshd
	// is back. sshd starts before loginwindow finishes logging the user in.
	afterRestart time.Duration
	// afterKick is how long a respawned loginwindow gets.
	afterKick time.Duration
	interval  time.Duration
}

var defaultGUISessionWait = guiSessionWait{
	afterRestart: 3 * time.Minute,
	afterKick:    30 * time.Second,
	interval:     5 * time.Second,
}

// ensureGUISession leaves the host with an Aqua session for user, restarting
// it at most once.
//
// EnableAutoLogin has already kicked loginwindow, which is enough on a host
// whose console sits at the login window. It is not enough on a host whose
// console Setup Assistant still holds from first boot (_mbsetupuser): the kick
// leaves that session in place, and auto-login only takes effect on the next
// boot. A restart is the recovery, so this restarts a host without the session
// and verifies the session afterwards. A host that already has it is left
// alone. Should the restart not bring it up, loginwindow is kicked once more,
// since a headless host may need that after any boot, before giving up.
func ensureGUISession(ctx context.Context, host guiSessionHost, user string, wait guiSessionWait) error {
	state, err := host.probeGUISession(ctx)
	if err != nil {
		return fmt.Errorf("probe gui session: %w", err)
	}
	if state.readyFor(user) {
		return nil
	}
	if !state.FileVaultOff {
		return &GUISessionError{User: user, State: state, RestartUnsafe: true,
			Reason: "FileVault is not off, which disables auto-login; not restarting a host that would stop at the unlock screen"}
	}

	if err := host.restart(ctx); err != nil {
		return fmt.Errorf("restart to apply auto-login (%s): %w", state.describe(), err)
	}
	state, ready, err := waitForGUISession(ctx, host, user, wait.afterRestart, wait.interval)
	if err != nil || ready {
		return err
	}

	if err := host.kickLoginwindow(ctx); err != nil {
		return fmt.Errorf("kick loginwindow after restart: %w", err)
	}
	state, ready, err = waitForGUISession(ctx, host, user, wait.afterKick, wait.interval)
	if err != nil || ready {
		return err
	}
	return &GUISessionError{User: user, State: state, Reason: "still missing after a restart and a loginwindow kick"}
}

func waitForGUISession(ctx context.Context, host guiSessionHost, user string, timeout, interval time.Duration) (GUISessionState, bool, error) {
	deadline := time.Now().Add(timeout)
	for {
		state, err := host.probeGUISession(ctx)
		if err == nil && state.readyFor(user) {
			return state, true, nil
		}
		if time.Now().After(deadline) {
			if err != nil {
				return state, false, fmt.Errorf("probe gui session: %w", err)
			}
			return state, false, nil
		}
		select {
		case <-ctx.Done():
			return state, false, ctx.Err()
		case <-time.After(interval):
		}
	}
}

// renderGUISessionProbeScript prints the console owner, whether user has an
// Aqua session, and FileVault's status, one `key=value` per line. No pipefail:
// grep -q exits on the first match, and launchctl's SIGPIPE must not count.
func renderGUISessionProbeScript(user string) string {
	return fmt.Sprintf(`set -u
uid=$(id -u %[1]s)
echo "console=$(stat -f %%Su /dev/console)"
if sudo -n launchctl print "gui/$uid" 2>/dev/null | grep -q 'session = Aqua'; then
  echo aqua=1
else
  echo aqua=0
fi
echo "filevault=$(sudo -n fdesetup status 2>/dev/null | head -n 1)"
`, shellQuote(user))
}

func parseGUISessionProbe(out string) (GUISessionState, error) {
	var state GUISessionState
	seen := map[string]bool{}
	for _, line := range strings.Split(out, "\n") {
		key, value, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok {
			continue
		}
		seen[key] = true
		switch key {
		case "console":
			state.ConsoleUser = value
		case "aqua":
			state.Aqua = value == "1"
		case "filevault":
			state.FileVaultOff = strings.HasPrefix(value, "FileVault is Off")
		}
	}
	for _, key := range []string{"console", "aqua", "filevault"} {
		if !seen[key] {
			return GUISessionState{}, fmt.Errorf("gui session probe printed no %s: %q", key, strings.TrimSpace(out))
		}
	}
	return state, nil
}

// sshGUISessionHost drives ensureGUISession over SSH. restart replaces client,
// so the caller continues on the session it leaves behind.
type sshGUISessionHost struct {
	client *ssh.Client
	ip     string
	user   string
	signer ssh.Signer
	hk     *HostKeyState

	restartTimeout time.Duration
	redialInterval time.Duration
}

func newSSHGUISessionHost(client *ssh.Client, ip, user string, signer ssh.Signer, hk *HostKeyState) *sshGUISessionHost {
	return &sshGUISessionHost{
		client:         client,
		ip:             ip,
		user:           user,
		signer:         signer,
		hk:             hk,
		restartTimeout: 10 * time.Minute,
		redialInterval: 15 * time.Second,
	}
}

func (h *sshGUISessionHost) probeGUISession(ctx context.Context) (GUISessionState, error) {
	out, err := RunCommandOutput(ctx, h.client, renderGUISessionProbeScript(h.user), nil)
	if err != nil {
		return GUISessionState{}, err
	}
	return parseGUISessionProbe(out)
}

func (h *sshGUISessionHost) kickLoginwindow(ctx context.Context) error {
	return RunCommand(ctx, h.client, "sudo -n launchctl kickstart -k system/com.apple.loginwindow")
}

// restart compares kern.boottime across the restart rather than waiting for
// SSH to drop and return: sshd keeps answering for the seconds before the
// detached shutdown runs, and a dial that lands there is the old boot.
func (h *sshGUISessionHost) restart(ctx context.Context) error {
	before, err := sshBootTime(ctx, h.client)
	if err != nil {
		return fmt.Errorf("read boot time: %w", err)
	}
	if err := RunCommand(ctx, h.client, osRestartScript); err != nil {
		return err
	}
	_ = h.client.Close()

	deadline := time.Now().Add(h.restartTimeout)
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(h.redialInterval):
		}
		if client, err := Dial(h.ip, h.user, h.signer, h.hk); err == nil {
			after, bootErr := sshBootTime(ctx, client)
			if bootErr == nil && after > before {
				h.client = client
				return nil
			}
			_ = client.Close()
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("host did not come back on a new boot within %s", h.restartTimeout)
		}
	}
}

func sshBootTime(ctx context.Context, client *ssh.Client) (int64, error) {
	out, err := RunCommandOutput(ctx, client, "sysctl -n kern.boottime", nil)
	if err != nil {
		return 0, err
	}
	return ParseKernBootTime(out)
}
