package bootstrap

import (
	"context"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"golang.org/x/crypto/ssh"
)

// osUpdateDir holds the detached jobs' logs and exit codes. A macOS install resets /private/var/tmp; /Users/Shared survives it.
const osUpdateDir = "/Users/Shared/tuist-os-update"

const (
	OSUpdateJobDownload = "download"
	OSUpdateJobInstall  = "install"
)

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
	OSUpdateJobAbsent  OSUpdateJobState = "absent"
	OSUpdateJobRunning OSUpdateJobState = "running"
	OSUpdateJobExited  OSUpdateJobState = "exited"
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
	osUpdateJobStateLine = regexp.MustCompile(`^(absent|running|exited)(?:\s+(-?\d+))?$`)
	secureTokenStatus    = regexp.MustCompile(`Secure token is (ENABLED|DISABLED)`)
)

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

// renderOSUpdateJobScript starts body detached from the SSH session and records its exit code beside its log.
func renderOSUpdateJobScript(dir, job, preamble, body string) string {
	return fmt.Sprintf(`set -eu
%[3]sdir=%[1]s
mkdir -p "$dir"
chmod 700 "$dir"
rm -f "$dir/%[2]s.exit" "$dir/%[2]s.log" "$dir/%[2]s.pid"
( set +e; trap '' HUP; %[4]s; echo $? > "$dir/%[2]s.exit" ) </dev/null >"$dir/%[2]s.log" 2>&1 &
echo $! > "$dir/%[2]s.pid"
`, shellQuote(dir), job, preamble, body)
}

func renderOSUpdateDownloadScript(dir, label string) string {
	return renderOSUpdateJobScript(dir, OSUpdateJobDownload, "",
		"sudo -n softwareupdate --download "+shellQuote(label))
}

// renderOSUpdateInstallScript reads the volume owner's password from stdin, so it never appears in a process's arguments.
func renderOSUpdateInstallScript(dir, label, user string) string {
	return renderOSUpdateJobScript(dir, OSUpdateJobInstall, "IFS= read -r pw\n",
		`printf '%s\n' "$pw" | sudo -n softwareupdate --install `+shellQuote(label)+
			" --restart --user "+shellQuote(user)+" --stdinpass")
}

func renderOSUpdateJobStateScript(dir, job string) string {
	return fmt.Sprintf(`dir=%[1]s
if [ -f "$dir/%[2]s.exit" ]; then
  echo "exited $(cat "$dir/%[2]s.exit")"
elif [ -f "$dir/%[2]s.pid" ] && kill -0 "$(cat "$dir/%[2]s.pid")" 2>/dev/null; then
  echo running
else
  echo absent
fi
tail -c 2000 "$dir/%[2]s.log" 2>/dev/null | tr '\r' '\n' | grep -v '^[[:space:]]*$' | tail -n 1
true
`, shellQuote(dir), job)
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

func (s *OSUpdateSession) StartDownload(ctx context.Context, label string) error {
	return RunCommand(ctx, s.client, renderOSUpdateDownloadScript(osUpdateDir, label))
}

func (s *OSUpdateSession) StartInstall(ctx context.Context, label, user, password string) error {
	return RunCommandWithStdin(ctx, s.client, renderOSUpdateInstallScript(osUpdateDir, label, user), strings.NewReader(password+"\n"))
}

func (s *OSUpdateSession) Job(ctx context.Context, job string) (OSUpdateJob, error) {
	out, err := RunCommandOutput(ctx, s.client, renderOSUpdateJobStateScript(osUpdateDir, job), nil)
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
