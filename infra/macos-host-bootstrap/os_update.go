package bootstrap

import (
	"context"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"golang.org/x/crypto/ssh"
)

// osUpdateRoot holds a directory per update, named by the update's ID, with its detached jobs' logs, pids and exit codes. A macOS install resets /private/var/tmp; /Users/Shared survives it.
const osUpdateRoot = "/Users/Shared/tuist-os-update"

var osUpdateIDPattern = regexp.MustCompile(`^[A-Za-z0-9-]+$`)

const (
	OSUpdateJobDownload = "download"
	OSUpdateJobInstall  = "install"
	OSUpdateJobErase    = "erase"
)

// OSInstaller is one entry of `softwareupdate --list-full-installers`.
type OSInstaller struct {
	Title   string
	Version string
	Build   string
}

// App is where `softwareupdate --fetch-full-installer` puts the installer: its
// title names the app, "macOS 27 Golden Gate" as "Install macOS 27 Golden Gate.app".
func (i OSInstaller) App() string {
	return "/Applications/Install " + i.Title + ".app"
}

// OSUpdate is one entry of `softwareupdate --list`.
type OSUpdate struct {
	Label   string
	Title   string
	Version string
}

// IsMacOS reports whether the entry is macOS rather than an app shipped through Software Update, such as Safari, whose versions overlap macOS's.
func (u OSUpdate) IsMacOS() bool {
	return strings.HasPrefix(u.Title, "macOS ")
}

type OSUpdateJobState string

const (
	// OSUpdateJobAbsent is a job the update never started.
	OSUpdateJobAbsent  OSUpdateJobState = "absent"
	OSUpdateJobRunning OSUpdateJobState = "running"
	OSUpdateJobExited  OSUpdateJobState = "exited"
	// OSUpdateJobLost is a started job whose process is gone without an exit
	// code, as when the host shuts down for the restart an install asked for.
	OSUpdateJobLost OSUpdateJobState = "lost"
)

// OSUpdateJob is the observed state of a detached download or install.
type OSUpdateJob struct {
	State    OSUpdateJobState
	ExitCode int
	LogTail  string
}

var (
	softwareUpdateLabel  = regexp.MustCompile(`^\*\s*Label:\s*(.+?)\s*$`)
	softwareUpdateTitle  = regexp.MustCompile(`Title:\s*(.+?),\s*Version:\s*([^,]+?)\s*,`)
	kernBootTimeSeconds  = regexp.MustCompile(`sec\s*=\s*(\d+)`)
	osUpdateJobStateLine = regexp.MustCompile(`^(absent|running|exited|lost)(?:\s+(-?\d+))?$`)
	secureTokenStatus    = regexp.MustCompile(`Secure token is (ENABLED|DISABLED)`)
	fullInstallerEntry   = regexp.MustCompile(`^\*\s*Title:\s*(.+?),\s*Version:\s*([^,]+?)\s*,.*\bBuild:\s*([^,\s]+)`)
	ioregSerialNumber    = regexp.MustCompile(`"IOPlatformSerialNumber"\s*=\s*"([^"]+)"`)
)

// ParseFullInstallerList parses `softwareupdate --list-full-installers` output.
func ParseFullInstallerList(out string) []OSInstaller {
	var installers []OSInstaller
	for _, line := range strings.Split(out, "\n") {
		if m := fullInstallerEntry.FindStringSubmatch(strings.TrimSpace(line)); m != nil {
			installers = append(installers, OSInstaller{Title: m[1], Version: m[2], Build: m[3]})
		}
	}
	return installers
}

// ParseIORegSerial reads the hardware serial from `ioreg -rd1 -c IOPlatformExpertDevice`.
func ParseIORegSerial(out string) (string, error) {
	m := ioregSerialNumber.FindStringSubmatch(out)
	if m == nil {
		return "", fmt.Errorf("no IOPlatformSerialNumber in %q", strings.TrimSpace(out))
	}
	return m[1], nil
}

// ParseSecureTokenStatus reads `sysadminctl -secureTokenStatus`, which reports on stderr and exits 0 even for an unknown user.
func ParseSecureTokenStatus(out string) (bool, error) {
	m := secureTokenStatus.FindStringSubmatch(out)
	if m == nil {
		return false, fmt.Errorf("unrecognised secure token status %q", strings.TrimSpace(out))
	}
	return m[1] == "ENABLED", nil
}

// ParseSoftwareUpdateList parses `softwareupdate --list` output.
func ParseSoftwareUpdateList(out string) []OSUpdate {
	var updates []OSUpdate
	var current *OSUpdate
	for _, line := range strings.Split(out, "\n") {
		if m := softwareUpdateLabel.FindStringSubmatch(line); m != nil {
			updates = append(updates, OSUpdate{Label: m[1]})
			current = &updates[len(updates)-1]
			continue
		}
		if current == nil {
			continue
		}
		if m := softwareUpdateTitle.FindStringSubmatch(line); m != nil {
			current.Title = m[1]
			current.Version = m[2]
		}
	}
	return updates
}

// ParseKernBootTime returns the Unix seconds in `sysctl -n kern.boottime` output.
func ParseKernBootTime(out string) (int64, error) {
	m := kernBootTimeSeconds.FindStringSubmatch(out)
	if m == nil {
		return 0, fmt.Errorf("unrecognised kern.boottime %q", strings.TrimSpace(out))
	}
	return strconv.ParseInt(m[1], 10, 64)
}

func parseOSUpdateJob(out string) (OSUpdateJob, error) {
	lines := strings.SplitN(strings.TrimRight(out, "\n"), "\n", 2)
	m := osUpdateJobStateLine.FindStringSubmatch(strings.TrimSpace(lines[0]))
	if m == nil {
		return OSUpdateJob{}, fmt.Errorf("unrecognised job state %q", lines[0])
	}
	job := OSUpdateJob{State: OSUpdateJobState(m[1])}
	if m[2] != "" {
		job.ExitCode, _ = strconv.Atoi(m[2])
	}
	if len(lines) > 1 {
		job.LogTail = strings.TrimSpace(lines[1])
	}
	return job, nil
}

// renderOSUpdateJobScript starts body detached from the SSH session and records its exit code beside its log, in the update's own directory. It removes every other update's directory, so a job an earlier update left, or a recycled pid, is never read as this update's.
func renderOSUpdateJobScript(root, id, job, preamble, body string) string {
	return fmt.Sprintf(`set -eu
%[4]sroot=%[1]s
dir=%[1]s/%[2]s
mkdir -p "$dir"
chmod 700 "$root" "$dir"
find "$root" -mindepth 1 -maxdepth 1 ! -name %[2]s -exec rm -rf {} +
rm -f "$dir/%[3]s.exit" "$dir/%[3]s.log" "$dir/%[3]s.pid"
( set +e; trap '' HUP; %[5]s; echo $? > "$dir/%[3]s.exit" ) </dev/null >"$dir/%[3]s.log" 2>&1 &
echo $! > "$dir/%[3]s.pid"
`, shellQuote(root), shellQuote(id), job, preamble, body)
}

func renderOSUpdateDownloadScript(root, id, label string) string {
	return renderOSUpdateJobScript(root, id, OSUpdateJobDownload, "",
		"sudo -n softwareupdate --download "+shellQuote(label))
}

// renderOSUpdateInstallScript reads the volume owner's password from stdin, so it never appears in a process's arguments.
func renderOSUpdateInstallScript(root, id, label, user string) string {
	return renderOSUpdateJobScript(root, id, OSUpdateJobInstall, "IFS= read -r pw\n",
		`printf '%s\n' "$pw" | sudo -n softwareupdate --install `+shellQuote(label)+
			" --restart --user "+shellQuote(user)+" --stdinpass")
}

func renderOSUpdateFetchInstallerScript(root, id, version string) string {
	return renderOSUpdateJobScript(root, id, OSUpdateJobDownload, "",
		"sudo -n softwareupdate --fetch-full-installer --full-installer-version "+shellQuote(version))
}

// renderOSUpdateEraseScript erases the startup volume and installs from the
// installer app. Like the install, it reads the volume owner's password from
// stdin, so it never appears in a process's arguments.
func renderOSUpdateEraseScript(root, id string, installer OSInstaller, user string) string {
	return renderOSUpdateJobScript(root, id, OSUpdateJobErase, "IFS= read -r pw\n",
		`printf '%s\n' "$pw" | sudo -n `+shellQuote(installer.App()+"/Contents/Resources/startosinstall")+
			" --eraseinstall --agreetolicense --forcequitapps --newvolumename 'Macintosh HD' --user "+shellQuote(user)+" --stdinpass")
}

// osRestartScript checks sudo while the session can still report a failure,
// then restarts the host detached from it, so the command returns before sshd
// goes down.
const osRestartScript = `set -eu
sudo -n true
( trap '' HUP; sleep 2; sudo -n shutdown -r now ) </dev/null >/dev/null 2>&1 &
`

func renderTailscaleStateReadScript(path string) string {
	return fmt.Sprintf("if sudo -n test -s %[1]s; then sudo -n cat %[1]s; fi\n", shellQuote(path))
}

func renderOSUpdateJobStateScript(root, id, job string) string {
	return fmt.Sprintf(`dir=%[1]s/%[2]s
if [ -f "$dir/%[3]s.exit" ]; then
  echo "exited $(cat "$dir/%[3]s.exit")"
elif [ -f "$dir/%[3]s.pid" ] && kill -0 "$(cat "$dir/%[3]s.pid")" 2>/dev/null; then
  echo running
elif [ -f "$dir/%[3]s.pid" ]; then
  echo lost
else
  echo absent
fi
tail -c 2000 "$dir/%[3]s.log" 2>/dev/null | tr '\r' '\n' | grep -v '^[[:space:]]*$' | tail -n 1
true
`, shellQuote(root), shellQuote(id), job)
}

func checkOSUpdateID(id string) error {
	if !osUpdateIDPattern.MatchString(id) {
		return fmt.Errorf("invalid update ID %q", id)
	}
	return nil
}

// OSUpdateSession is one SSH connection used to drive an in-place macOS update.
type OSUpdateSession struct {
	client *ssh.Client
	hk     *HostKeyState
}

func OpenOSUpdateSession(ip, user string, privateKey []byte, knownFingerprint string) (*OSUpdateSession, error) {
	signer, err := ssh.ParsePrivateKey(privateKey)
	if err != nil {
		return nil, fmt.Errorf("parse ssh key: %w", err)
	}
	hk := NewHostKeyState(knownFingerprint)
	client, err := Dial(ip, user, signer, hk)
	if err != nil {
		return nil, err
	}
	return &OSUpdateSession{client: client, hk: hk}, nil
}

func (s *OSUpdateSession) Close() error {
	return s.client.Close()
}

// Fingerprint is the host key the host presented.
func (s *OSUpdateSession) Fingerprint() string {
	return s.hk.Observed()
}

func (s *OSUpdateSession) Version(ctx context.Context) (string, error) {
	out, err := RunCommandOutput(ctx, s.client, "sw_vers -productVersion", nil)
	return strings.TrimSpace(out), err
}

func (s *OSUpdateSession) BootTime(ctx context.Context) (int64, error) {
	out, err := RunCommandOutput(ctx, s.client, "sysctl -n kern.boottime", nil)
	if err != nil {
		return 0, err
	}
	return ParseKernBootTime(out)
}

func (s *OSUpdateSession) ListUpdates(ctx context.Context) ([]OSUpdate, error) {
	out, err := RunCommandOutput(ctx, s.client, "softwareupdate --list 2>&1", nil)
	if err != nil {
		return nil, err
	}
	return ParseSoftwareUpdateList(out), nil
}

func (s *OSUpdateSession) StartDownload(ctx context.Context, id, label string) error {
	if err := checkOSUpdateID(id); err != nil {
		return err
	}
	return RunCommand(ctx, s.client, renderOSUpdateDownloadScript(osUpdateRoot, id, label))
}

func (s *OSUpdateSession) StartInstall(ctx context.Context, id, label, user, password string) error {
	if err := checkOSUpdateID(id); err != nil {
		return err
	}
	return RunCommandWithStdin(ctx, s.client, renderOSUpdateInstallScript(osUpdateRoot, id, label, user), strings.NewReader(password+"\n"))
}

func (s *OSUpdateSession) ListFullInstallers(ctx context.Context) ([]OSInstaller, error) {
	out, err := RunCommandOutput(ctx, s.client, "softwareupdate --list-full-installers 2>&1", nil)
	if err != nil {
		return nil, err
	}
	return ParseFullInstallerList(out), nil
}

func (s *OSUpdateSession) StartFetchInstaller(ctx context.Context, id, version string) error {
	if err := checkOSUpdateID(id); err != nil {
		return err
	}
	return RunCommand(ctx, s.client, renderOSUpdateFetchInstallerScript(osUpdateRoot, id, version))
}

func (s *OSUpdateSession) StartErase(ctx context.Context, id string, installer OSInstaller, user, password string) error {
	if err := checkOSUpdateID(id); err != nil {
		return err
	}
	return RunCommandWithStdin(ctx, s.client, renderOSUpdateEraseScript(osUpdateRoot, id, installer, user), strings.NewReader(password+"\n"))
}

func (s *OSUpdateSession) Serial(ctx context.Context) (string, error) {
	out, err := RunCommandOutput(ctx, s.client, "ioreg -rd1 -c IOPlatformExpertDevice", nil)
	if err != nil {
		return "", err
	}
	return ParseIORegSerial(out)
}

func (s *OSUpdateSession) Restart(ctx context.Context) error {
	return RunCommand(ctx, s.client, osRestartScript)
}

// TailscaleState is tailscaled's state file, or nil on a host that has none.
func (s *OSUpdateSession) TailscaleState(ctx context.Context) ([]byte, error) {
	out, err := RunCommandOutput(ctx, s.client, renderTailscaleStateReadScript(tailscaleStatePath), nil)
	if err != nil {
		return nil, err
	}
	if out == "" {
		return nil, nil
	}
	return []byte(out), nil
}

// Job reports the named job of the update with this ID; another update's job reads as absent.
func (s *OSUpdateSession) Job(ctx context.Context, id, job string) (OSUpdateJob, error) {
	if err := checkOSUpdateID(id); err != nil {
		return OSUpdateJob{}, err
	}
	out, err := RunCommandOutput(ctx, s.client, renderOSUpdateJobStateScript(osUpdateRoot, id, job), nil)
	if err != nil {
		return OSUpdateJob{}, err
	}
	return parseOSUpdateJob(out)
}

// SecureTokenEnabled reports whether user holds a secure token, without which softwareupdate cannot authorise an install as them.
func (s *OSUpdateSession) SecureTokenEnabled(ctx context.Context, user string) (bool, error) {
	out, err := RunCommandOutput(ctx, s.client, "sysadminctl -secureTokenStatus "+shellQuote(user)+" 2>&1", nil)
	if err != nil {
		return false, err
	}
	return ParseSecureTokenStatus(out)
}

// ConsoleUser is the owner of /dev/console: the auto-login user once logged in, root at the login window.
func (s *OSUpdateSession) ConsoleUser(ctx context.Context) (string, error) {
	out, err := RunCommandOutput(ctx, s.client, "stat -f %Su /dev/console", nil)
	return strings.TrimSpace(out), err
}
