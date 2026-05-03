// Package bootstrap turns a freshly-provisioned Scaleway Mac mini into
// a tart-kubelet-ready cluster Node.
//
// Each Mac mini joins the cluster as a real `Node` via tart-kubelet
// — a small kubelet-shaped agent that watches the API server for Pods
// scheduled to its Node and runs them as Tart VMs locally. From the
// cluster's perspective, every Mac mini is a standalone Node with
// kubernetes.io/os=darwin.
//
// Steps, in order, idempotent on retry:
//  1. Wait for SSH (host has just booted from a Scaleway image).
//  2. Grant the SSH user passwordless sudo using the OS-default password.
//  3. Configure GUI auto-login via /etc/kcpassword + autoLoginUser
//     so Virtualization.framework has a live console session (Tart's
//     hard requirement).
//  4. Set the macOS hostname to the CR name so tart-kubelet's default
//     Node name lines up with the inventory CR.
//  5. Install Homebrew + Tart.
//  6. Drop the kubeconfig the controller built for this host.
//  7. Download the tart-kubelet binary.
//  8. Write the launchd plist with this host's flags + load it.
//
// After step 8 the agent on the Mac mini registers a Node and starts
// reconciling Pods. The MachineReconciler flips Machine.Status.Ready
// when this returns nil.
package bootstrap

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"net"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"
)

// Config drives the bootstrap.
type Config struct {
	IP            string
	SSHUser       string
	SudoPassword  string
	SSHPrivateKey []byte

	// NodeName is the cluster Node name tart-kubelet should register.
	// Matches the ScalewayAppleSiliconMachine CR name so `kubectl get
	// nodes` reflects the inventory.
	NodeName string

	// Kubeconfig is the YAML kubeconfig the controller built for this
	// host (contains a long-lived ServiceAccount token + the API
	// server's external URL + CA bundle). Dropped at
	// /etc/tart-kubelet/kubeconfig.
	Kubeconfig string

	// TartKubeletBinary is the in-memory bytes of the darwin/arm64
	// tart-kubelet binary, baked into the operator image and read at
	// startup. We upload these bytes over SSH to /usr/local/bin on the
	// Mac mini — no external URL, no separate release artifact.
	TartKubeletBinary []byte

	// HostCPU / HostMemoryMB / MaxPods are advertised on the Node.
	HostCPU      int
	HostMemoryMB int
	MaxPods      int

	// KnownHostFingerprint is the SHA256 fingerprint of the SSH
	// server's host key, persisted by the controller after the first
	// successful bootstrap. When empty (first reconcile, fleet
	// expansion) the SSH client uses TOFU: it accepts the key the
	// host presents on the first dial and the controller persists it
	// for next time. When non-empty every dial verifies against it
	// and refuses to connect on mismatch. Replaces a prior
	// `ssh.InsecureIgnoreHostKey()` that left every bootstrap open
	// to a network MITM (kubeconfig + tart-kubelet binary injection).
	KnownHostFingerprint string
}

// Run executes the bootstrap. Idempotent: re-running on a partially-
// bootstrapped host completes the missing steps without redoing the
// finished ones.
//
// Returns the SSH host fingerprint observed during the dial. The
// caller persists it so future reconciles verify the same host
// (TOFU). When cfg.KnownHostFingerprint was already set, the returned
// value equals it and Run rejects any mismatch as an error.
func Run(ctx context.Context, cfg Config) (string, error) {
	signer, err := ssh.ParsePrivateKey(cfg.SSHPrivateKey)
	if err != nil {
		return "", fmt.Errorf("parse ssh key: %w", err)
	}

	hk := newHostKeyState(cfg.KnownHostFingerprint)

	if err := waitForSSH(ctx, cfg.IP, cfg.SSHUser, signer, hk); err != nil {
		return "", err
	}

	client, err := dial(cfg.IP, cfg.SSHUser, signer, hk)
	if err != nil {
		return "", err
	}
	defer client.Close()

	if err := enablePasswordlessSudo(ctx, client, cfg.SSHUser, cfg.SudoPassword); err != nil {
		return hk.observed(), fmt.Errorf("passwordless sudo: %w", err)
	}
	if err := enableAutoLogin(ctx, client, cfg.SSHUser, cfg.SudoPassword); err != nil {
		return hk.observed(), fmt.Errorf("auto-login: %w", err)
	}
	if cfg.NodeName != "" {
		if err := setHostname(ctx, client, cfg.NodeName); err != nil {
			return hk.observed(), fmt.Errorf("set hostname: %w", err)
		}
	}
	if err := installTart(ctx, client); err != nil {
		return hk.observed(), fmt.Errorf("install tart: %w", err)
	}
	if err := writeKubeconfig(ctx, client, cfg.Kubeconfig); err != nil {
		return hk.observed(), fmt.Errorf("write kubeconfig: %w", err)
	}
	if err := installTartKubelet(ctx, client, cfg.TartKubeletBinary); err != nil {
		return hk.observed(), fmt.Errorf("install tart-kubelet: %w", err)
	}
	if err := loadTartKubeletLaunchd(ctx, client, cfg); err != nil {
		return hk.observed(), fmt.Errorf("load launchd job: %w", err)
	}
	return hk.observed(), nil
}

// UpdateTartKubelet rolls a new tart-kubelet binary onto an
// already-bootstrapped Mac mini. Refreshes the kubeconfig (token
// rotation, server-URL changes, or hosts that were bootstrapped before
// tart-kubelet existed at all), uploads the latest binary, and reloads
// the launchd job.
//
// Skips the one-shot host prep (sudo, auto-login, hostname, Tart) —
// those don't change between updates. The launchd `bootout`+`bootstrap`
// cycle runs unconditionally — it's a ~1-second agent restart and Tart
// VMs survive `nohup`-detached, so workloads are unaffected. The
// kubelet's startup state-recovery pass re-binds them on the new agent.
//
// Returns the observed host fingerprint for the same reason Run does.
// On the update path KnownHostFingerprint is normally already set (the
// bootstrap reconcile populated it), so this is a verification rather
// than a capture.
func UpdateTartKubelet(ctx context.Context, cfg Config) (string, error) {
	signer, err := ssh.ParsePrivateKey(cfg.SSHPrivateKey)
	if err != nil {
		return "", fmt.Errorf("parse ssh key: %w", err)
	}
	hk := newHostKeyState(cfg.KnownHostFingerprint)
	client, err := dial(cfg.IP, cfg.SSHUser, signer, hk)
	if err != nil {
		return "", err
	}
	defer client.Close()

	if err := writeKubeconfig(ctx, client, cfg.Kubeconfig); err != nil {
		return hk.observed(), fmt.Errorf("refresh kubeconfig: %w", err)
	}
	if err := installTartKubelet(ctx, client, cfg.TartKubeletBinary); err != nil {
		return hk.observed(), fmt.Errorf("install tart-kubelet: %w", err)
	}
	if err := loadTartKubeletLaunchd(ctx, client, cfg); err != nil {
		return hk.observed(), fmt.Errorf("reload launchd job: %w", err)
	}
	return hk.observed(), nil
}

// setHostname makes the macOS hostname match the CR name, so
// `os.Hostname()` inside tart-kubelet (the default --node-name) lines
// up with the inventory. The operator passes --node-name explicitly
// regardless; this is belt-and-braces.
func setHostname(ctx context.Context, client *ssh.Client, name string) error {
	script := fmt.Sprintf(`set -euo pipefail
sudo scutil --set HostName %[1]s
sudo scutil --set LocalHostName %[1]s
sudo scutil --set ComputerName %[1]s
`, shellQuote(name))
	return runCommand(ctx, client, script)
}

// writeKubeconfig drops the controller-built kubeconfig at the
// well-known path tart-kubelet looks for.
func writeKubeconfig(ctx context.Context, client *ssh.Client, kubeconfig string) error {
	if kubeconfig == "" {
		return fmt.Errorf("empty kubeconfig in bootstrap config")
	}
	script := `set -euo pipefail
sudo mkdir -p /etc/tart-kubelet
sudo tee /etc/tart-kubelet/kubeconfig >/dev/null
sudo chmod 0600 /etc/tart-kubelet/kubeconfig
`
	return runCommandWithStdin(ctx, client, script, kubeconfig)
}

// installTartKubelet uploads the operator-baked tart-kubelet binary
// to /usr/local/bin/tart-kubelet on the Mac mini and marks it
// executable. We pipe the bytes via stdin into `sudo tee` rather than
// downloading from an external URL — the operator's image is the
// single source of truth for the kubelet version, so deploying a new
// operator image rolls a new kubelet across the fleet.
//
// Always overwrites. The reconciler's drift detection prevents
// unnecessary calls (it compares the operator's binary SHA to the
// last-applied SHA in the CR's status).
func installTartKubelet(ctx context.Context, client *ssh.Client, binary []byte) error {
	if len(binary) == 0 {
		return fmt.Errorf("tart-kubelet binary is empty")
	}
	script := `set -euo pipefail
sudo mkdir -p /usr/local/bin
sudo tee /usr/local/bin/tart-kubelet >/dev/null
sudo chmod 0755 /usr/local/bin/tart-kubelet
`
	return runCommandWithStdin(ctx, client, script, string(binary))
}

// loadTartKubeletLaunchd writes /Library/LaunchDaemons/dev.tuist.tart-kubelet.plist
// with this host's flags substituted in, fixes ownership on the
// kubelet's writable paths so the SSH user owns them (the launchd job
// runs as that user — see the comment in renderLaunchdPlist), then
// `launchctl bootstrap`s it. Idempotent across reruns.
func loadTartKubeletLaunchd(ctx context.Context, client *ssh.Client, cfg Config) error {
	plist := renderLaunchdPlist(cfg)
	script := fmt.Sprintf(`set -euo pipefail
PLIST=/Library/LaunchDaemons/dev.tuist.tart-kubelet.plist
sudo tee "$PLIST" >/dev/null
sudo chown root:wheel "$PLIST"
sudo chmod 0644 "$PLIST"
# Apple's Virtualization.framework requires the calling process to be
# owned by the user with the live GUI console session — see
# renderLaunchdPlist's UserName field. Hand kubelet-writable paths to
# that user so it can write VM logs / userdata / read its kubeconfig.
sudo mkdir -p /var/log/tart-vms /var/lib/tart-userdata /etc/tart-kubelet
sudo touch /var/log/tart-kubelet.log
sudo chown -R %[1]s:staff /var/log/tart-vms /var/lib/tart-userdata /var/log/tart-kubelet.log
sudo chown %[1]s:staff /etc/tart-kubelet/kubeconfig
sudo chmod 0600 /etc/tart-kubelet/kubeconfig
# launchctl bootstrap is the modern API; bootout first to make this
# idempotent across reruns with new args.
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"
`, shellQuote(cfg.SSHUser))
	return runCommandWithStdin(ctx, client, script, plist)
}

func renderLaunchdPlist(cfg Config) string {
	cpu := cfg.HostCPU
	if cpu == 0 {
		cpu = 8
	}
	mem := cfg.HostMemoryMB
	if mem == 0 {
		mem = 16384
	}
	maxPods := cfg.MaxPods
	if maxPods == 0 {
		maxPods = 8
	}
	user := cfg.SSHUser
	if user == "" {
		user = "m1"
	}
	// Run tart-kubelet as the SSH user (m1). Apple's
	// Virtualization.framework requires the calling process to be the
	// same user that holds the live GUI console session — Tart's
	// "Failed to get current host key" otherwise. The auto-login we
	// configured in `enableAutoLogin` puts m1 on the console at boot;
	// matching the launchd job's UserName lines tart up with that
	// session.
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.tuist.tart-kubelet</string>
  <key>UserName</key>
  <string>%[5]s</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/tart-kubelet</string>
    <string>--node-name=%[1]s</string>
    <string>--kubeconfig=/etc/tart-kubelet/kubeconfig</string>
    <string>--host-cpu=%[2]d</string>
    <string>--host-memory-mb=%[3]d</string>
    <string>--max-pods=%[4]d</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>/var/log/tart-kubelet.log</string>
  <key>StandardErrorPath</key><string>/var/log/tart-kubelet.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>/Users/%[5]s</string>
    <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
`, cfg.NodeName, cpu, mem, maxPods, user)
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// hostKeyState wires SSH dials to the persisted-fingerprint TOFU
// flow. The same instance is shared across waitForSSH retries and the
// real dial: when we capture a fingerprint on a probe dial the real
// dial verifies against it, so an attacker can't inject a different
// host key between the two.
type hostKeyState struct {
	mu       sync.Mutex
	expected string // empty until first observation; persisted by caller
	captured string // SHA256 of the key the host actually presented
}

func newHostKeyState(known string) *hostKeyState {
	return &hostKeyState{expected: known}
}

// observed returns the fingerprint the host actually presented during
// the dial, or the expected value if the dial never happened. The
// controller persists this so the next reconcile starts with a known
// host.
func (h *hostKeyState) observed() string {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.captured != "" {
		return h.captured
	}
	return h.expected
}

func (h *hostKeyState) callback() ssh.HostKeyCallback {
	return func(_ string, _ net.Addr, key ssh.PublicKey) error {
		got := ssh.FingerprintSHA256(key)
		h.mu.Lock()
		defer h.mu.Unlock()
		// Mid-bootstrap rotation guard: any state that has already
		// observed a key requires every subsequent observation to
		// match it. Without this, two dials in a single bootstrap
		// (probe + real) could see different keys and the second
		// would silently TOFU over the first.
		if h.captured != "" && h.captured != got {
			return fmt.Errorf("host key fingerprint changed mid-bootstrap: previously %s, now %s", h.captured, got)
		}
		// Persisted-fingerprint verification. When the operator
		// already knows what key to expect (Secret carries
		// host-fingerprint from a prior reconcile), refuse anything
		// else regardless of TOFU state.
		if h.expected != "" && got != h.expected {
			return fmt.Errorf("host key fingerprint mismatch: expected %s, got %s", h.expected, got)
		}
		h.captured = got
		return nil
	}
}

func dial(ip, user string, signer ssh.Signer, hk *hostKeyState) (*ssh.Client, error) {
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: hk.callback(),
		Timeout:         15 * time.Second,
	}
	return ssh.Dial("tcp", ip+":22", cfg)
}

func waitForSSH(ctx context.Context, ip, user string, signer ssh.Signer, hk *hostKeyState) error {
	deadline := time.Now().Add(5 * time.Minute)
	for {
		if time.Now().After(deadline) {
			return fmt.Errorf("SSH not available after 5m at %s", ip)
		}
		client, err := dial(ip, user, signer, hk)
		if err == nil {
			client.Close()
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(10 * time.Second):
		}
	}
}

// enablePasswordlessSudo writes a sudoers.d entry for the SSH user. We
// authenticate the initial sudo with the OS-default password Scaleway
// returns at server creation time; subsequent sudo calls don't need it.
func enablePasswordlessSudo(ctx context.Context, client *ssh.Client, user, password string) error {
	script := fmt.Sprintf(`set -euo pipefail
if [ -f /etc/sudoers.d/%[1]s-nopasswd ]; then exit 0; fi
echo '%[2]s' | sudo -S tee /etc/sudoers.d/%[1]s-nopasswd > /dev/null <<EOF
%[1]s ALL=(ALL) NOPASSWD: ALL
EOF
sudo chmod 440 /etc/sudoers.d/%[1]s-nopasswd
`, user, password)
	return runCommand(ctx, client, script)
}

// enableAutoLogin sets the macOS auto-login flag so a desktop session
// exists at boot. Tart's Virtualization.framework requires a live
// console session — without this, every `tart run` returns
// "Virtualization is not available because no graphic console is
// available".
//
// macOS implements auto-login via:
//   - /etc/kcpassword (XOR-encoded password with Apple's well-known key)
//   - com.apple.loginwindow.autoLoginUser preference
func enableAutoLogin(ctx context.Context, client *ssh.Client, user, password string) error {
	encoded := encodeKCPassword(password)
	// Stage the binary kcpassword via base64 to avoid TTY issues.
	script := fmt.Sprintf(`set -euo pipefail
if defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null | grep -q '%[1]s'; then exit 0; fi
echo '%[2]s' | base64 -d | sudo tee /etc/kcpassword > /dev/null
sudo chmod 600 /etc/kcpassword
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser '%[1]s'
`, user, encoded)
	return runCommand(ctx, client, script)
}

// kcpasswordKey is Apple's well-known XOR cipher used to obfuscate
// the auto-login password in /etc/kcpassword. Not security; just
// unicode/locale safety.
var kcpasswordKey = []byte{0x7d, 0x89, 0x52, 0x23, 0xd2, 0xbc, 0xdd, 0xea, 0xa3, 0xb9, 0x1f}

func encodeKCPassword(password string) string {
	src := []byte(password)
	// Pad to next multiple of len(key) with NULs (matches Apple's behavior).
	pad := len(kcpasswordKey) - (len(src) % len(kcpasswordKey))
	for i := 0; i < pad; i++ {
		src = append(src, 0)
	}
	for i := range src {
		src[i] ^= kcpasswordKey[i%len(kcpasswordKey)]
	}
	// base64 for transport via SSH stdin.
	return b64(src)
}

// installTart installs Homebrew + Tart on the host. Idempotent.
func installTart(ctx context.Context, client *ssh.Client) error {
	script := `set -euo pipefail
if [ ! -x /opt/homebrew/bin/brew ]; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
if ! /opt/homebrew/bin/brew list --formula tart >/dev/null 2>&1; then
    /opt/homebrew/bin/brew tap cirruslabs/cli >/dev/null 2>&1 || true
    /opt/homebrew/bin/brew install cirruslabs/cli/tart
fi
sudo ln -sf /opt/homebrew/bin/tart /usr/local/bin/tart 2>/dev/null || \
    (sudo mkdir -p /usr/local/bin && sudo ln -sf /opt/homebrew/bin/tart /usr/local/bin/tart)
/opt/homebrew/bin/tart --version
`
	return runCommand(ctx, client, script)
}

// === SSH helpers ===========================================================

func runCommand(ctx context.Context, client *ssh.Client, cmd string) error {
	return runCommandWithStdin(ctx, client, cmd, "")
}

func runCommandWithStdin(ctx context.Context, client *ssh.Client, cmd, stdin string) error {
	session, err := client.NewSession()
	if err != nil {
		return err
	}
	defer session.Close()

	if stdin != "" {
		session.Stdin = strings.NewReader(stdin)
	}

	var stderr bytes.Buffer
	session.Stderr = &stderr

	done := make(chan error, 1)
	go func() {
		done <- session.Run(cmd)
	}()
	select {
	case <-ctx.Done():
		_ = session.Signal(ssh.SIGTERM)
		return ctx.Err()
	case err := <-done:
		if err != nil {
			return fmt.Errorf("ssh exec %q: %w (stderr: %s)", cmd, err, stderr.String())
		}
		return nil
	}
}

func b64(b []byte) string {
	return base64.StdEncoding.EncodeToString(b)
}
