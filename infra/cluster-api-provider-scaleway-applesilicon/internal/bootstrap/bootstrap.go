// Package bootstrap turns a freshly-provisioned Scaleway Mac mini into
// a Tart-ready compute host.
//
// We DO NOT install kubelet on the Mac mini. The Mac mini is a "dumb"
// Tart server: the in-cluster Virtual Kubelet provider
// (infra/vk-applesilicon) SSHes in to drive `tart pull/clone/run/...`
// against this host. From the cluster's perspective, Mac minis show up
// as slots on a single virtual Node, not as standalone k8s Nodes.
//
// Steps, in order, idempotent on retry:
//   1. Wait for SSH (host has just booted from a Scaleway image).
//   2. Grant the SSH user passwordless sudo using the OS-default password.
//   3. Configure GUI auto-login via /etc/kcpassword + autoLoginUser
//      so Virtualization.framework has a live console session (Tart's
//      hard requirement).
//   4. Install Homebrew + Tart if missing.
//
// After step 4 the host is ready for the VK provider to claim. The
// MachineReconciler flips Machine.Status.Ready=true when this returns
// nil.
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
	if err := installTart(ctx, client); err != nil {
		return fmt.Errorf("install tart: %w", err)
	}
	return nil
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
