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
	"strings"
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

	// TartKubeletURL is the HTTPS URL of the darwin/arm64 binary to
	// install. Pinned per fleet via Helm values; the operator threads
	// it through here.
	TartKubeletURL string

	// HostCPU / HostMemoryMB / MaxPods are advertised on the Node.
	HostCPU      int
	HostMemoryMB int
	MaxPods      int
}

// Run executes the bootstrap. Idempotent: re-running on a partially-
// bootstrapped host completes the missing steps without redoing the
// finished ones.
func Run(ctx context.Context, cfg Config) error {
	signer, err := ssh.ParsePrivateKey(cfg.SSHPrivateKey)
	if err != nil {
		return fmt.Errorf("parse ssh key: %w", err)
	}

	if err := waitForSSH(ctx, cfg.IP, cfg.SSHUser, signer); err != nil {
		return err
	}

	client, err := dial(cfg.IP, cfg.SSHUser, signer)
	if err != nil {
		return err
	}
	defer client.Close()

	if err := enablePasswordlessSudo(ctx, client, cfg.SSHUser, cfg.SudoPassword); err != nil {
		return fmt.Errorf("passwordless sudo: %w", err)
	}
	if err := enableAutoLogin(ctx, client, cfg.SSHUser, cfg.SudoPassword); err != nil {
		return fmt.Errorf("auto-login: %w", err)
	}
	if cfg.NodeName != "" {
		if err := setHostname(ctx, client, cfg.NodeName); err != nil {
			return fmt.Errorf("set hostname: %w", err)
		}
	}
	if err := installTart(ctx, client); err != nil {
		return fmt.Errorf("install tart: %w", err)
	}
	if err := writeKubeconfig(ctx, client, cfg.Kubeconfig); err != nil {
		return fmt.Errorf("write kubeconfig: %w", err)
	}
	if err := installTartKubelet(ctx, client, cfg.TartKubeletURL); err != nil {
		return fmt.Errorf("install tart-kubelet: %w", err)
	}
	if err := loadTartKubeletLaunchd(ctx, client, cfg); err != nil {
		return fmt.Errorf("load launchd job: %w", err)
	}
	return nil
}

// UpdateTartKubelet rolls a new tart-kubelet binary onto an
// already-bootstrapped Mac mini. Re-runs only the install + launchd
// reload steps; skips the host-level bootstrap (sudo, auto-login,
// hostname, Tart, kubeconfig) which doesn't change between updates.
//
// The on-disk install is idempotent on URL: if the binary's URL hash
// matches the marker file, the curl is skipped. The launchd
// `bootout`+`bootstrap` cycle runs unconditionally — it's a ~1-second
// agent restart and Tart VMs running on the host are detached via
// `nohup` so they're unaffected. tart-kubelet's startup state-recovery
// pass picks them back up on the new agent.
func UpdateTartKubelet(ctx context.Context, cfg Config) error {
	signer, err := ssh.ParsePrivateKey(cfg.SSHPrivateKey)
	if err != nil {
		return fmt.Errorf("parse ssh key: %w", err)
	}
	client, err := dial(cfg.IP, cfg.SSHUser, signer)
	if err != nil {
		return err
	}
	defer client.Close()

	if err := installTartKubelet(ctx, client, cfg.TartKubeletURL); err != nil {
		return fmt.Errorf("install tart-kubelet: %w", err)
	}
	if err := loadTartKubeletLaunchd(ctx, client, cfg); err != nil {
		return fmt.Errorf("reload launchd job: %w", err)
	}
	return nil
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

// installTartKubelet downloads the tart-kubelet binary to
// /usr/local/bin. Idempotent: re-running with the same URL skips the
// download if the marker file matches.
func installTartKubelet(ctx context.Context, client *ssh.Client, url string) error {
	if url == "" {
		return fmt.Errorf("empty TartKubeletURL")
	}
	script := fmt.Sprintf(`set -euo pipefail
mkdir -p /tmp/tart-kubelet-install
URL_HASH=$(echo -n %[1]s | shasum -a 256 | awk '{print $1}')
MARKER=/usr/local/bin/.tart-kubelet.url.sha
if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$URL_HASH" ] && [ -x /usr/local/bin/tart-kubelet ]; then exit 0; fi
curl -fsSL %[1]s -o /tmp/tart-kubelet-install/tart-kubelet
chmod 0755 /tmp/tart-kubelet-install/tart-kubelet
sudo mv /tmp/tart-kubelet-install/tart-kubelet /usr/local/bin/tart-kubelet
echo "$URL_HASH" | sudo tee "$MARKER" >/dev/null
`, shellQuote(url))
	return runCommand(ctx, client, script)
}

// loadTartKubeletLaunchd writes /Library/LaunchDaemons/dev.tuist.tart-kubelet.plist
// with this host's flags substituted in, then `launchctl bootstrap`s it
// (replaces any prior load idempotently).
func loadTartKubeletLaunchd(ctx context.Context, client *ssh.Client, cfg Config) error {
	plist := renderLaunchdPlist(cfg)
	script := `set -euo pipefail
PLIST=/Library/LaunchDaemons/dev.tuist.tart-kubelet.plist
sudo tee "$PLIST" >/dev/null
sudo chown root:wheel "$PLIST"
sudo chmod 0644 "$PLIST"
# launchctl bootstrap is the modern API; bootout first to make this
# idempotent across reruns with new args.
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"
`
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
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.tuist.tart-kubelet</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/tart-kubelet</string>
    <string>--node-name=%s</string>
    <string>--kubeconfig=/etc/tart-kubelet/kubeconfig</string>
    <string>--host-cpu=%d</string>
    <string>--host-memory-mb=%d</string>
    <string>--max-pods=%d</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>/var/log/tart-kubelet.log</string>
  <key>StandardErrorPath</key><string>/var/log/tart-kubelet.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>/var/root</string>
    <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
`, cfg.NodeName, cpu, mem, maxPods)
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func dial(ip, user string, signer ssh.Signer) (*ssh.Client, error) {
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         15 * time.Second,
	}
	return ssh.Dial("tcp", ip+":22", cfg)
}

func waitForSSH(ctx context.Context, ip, user string, signer ssh.Signer) error {
	deadline := time.Now().Add(5 * time.Minute)
	for {
		if time.Now().After(deadline) {
			return fmt.Errorf("SSH not available after 5m at %s", ip)
		}
		client, err := dial(ip, user, signer)
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
