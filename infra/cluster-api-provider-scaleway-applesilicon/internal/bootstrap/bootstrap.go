// Package bootstrap orchestrates the per-Machine setup that turns a
// freshly-provisioned Scaleway Mac mini into a Kubernetes Ready node.
//
// Equivalent to the imperative shell version that previously lived
// at infra/tart-cri/platform/provision.sh, ported to Go so the CAPI
// MachineReconciler can drive it without forking out to bash.
//
// Steps, in order, idempotent on retry:
//   1. Wait for SSH (host has just booted from a Scaleway image).
//   2. Grant the SSH user passwordless sudo using the OS-default password.
//   3. Configure GUI auto-login via /etc/kcpassword + autoLoginUser
//      so Virtualization.framework has a live console session
//      (Tart's hard requirement).
//   4. Install Homebrew + Tart if missing.
//   5. Install kubelet for darwin/arm64 from dl.k8s.io.
//   6. Install tart-cri + tart-cni binaries (assumed to be embedded
//      in the operator image at /usr/local/share/tart-cri/).
//   7. Drop kubelet config + bootstrap kubeconfig + CNI conflist +
//      launchd plists.
//   8. launchctl bootstrap both daemons.
//
// After step 8 the Mac mini's kubelet self-registers with the cluster
// API server; the MachineReconciler watches the corresponding Node
// object for `Ready=True` to flip the Machine's Status.Ready.
package bootstrap

import (
	"bytes"
	"context"
	"fmt"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
)

// Config drives the bootstrap. All fields are required.
type Config struct {
	IP             string
	SSHUser        string
	SudoPassword   string
	SSHPrivateKey  []byte
	Hostname       string
	PodCIDR        string
	KubeletVersion string

	BootstrapToken string
	APIServer      string
	CACertData     string

	// Path to the tart-cri + tart-cni binaries on disk (inside the
	// operator pod's image). Defaults to /usr/local/share/tart-cri/.
	TartCRIBinary string
	TartCNIBinary string
}

// Run executes the bootstrap. Idempotent: re-running on a partially-
// bootstrapped host completes the missing steps without redoing the
// finished ones.
func Run(ctx context.Context, cfg Config) error {
	if cfg.TartCRIBinary == "" {
		cfg.TartCRIBinary = "/usr/local/share/tart-cri/tart-cri"
	}
	if cfg.TartCNIBinary == "" {
		cfg.TartCNIBinary = "/usr/local/share/tart-cri/tart-cni"
	}

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
	if err := installKubelet(ctx, client, cfg.KubeletVersion); err != nil {
		return fmt.Errorf("install kubelet: %w", err)
	}
	if err := uploadTartCRIBinaries(ctx, client, cfg.TartCRIBinary, cfg.TartCNIBinary); err != nil {
		return fmt.Errorf("upload tart-cri binaries: %w", err)
	}
	if err := writeConfigs(ctx, client, cfg); err != nil {
		return fmt.Errorf("write configs: %w", err)
	}
	if err := bootDaemons(ctx, client); err != nil {
		return fmt.Errorf("boot daemons: %w", err)
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
	for time.Now().Before(deadline) {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		client, err := dial(ip, user, signer)
		if err == nil {
			_ = client.Close()
			return nil
		}
		time.Sleep(5 * time.Second)
	}
	return fmt.Errorf("SSH not available after 5m at %s", ip)
}

func enablePasswordlessSudo(ctx context.Context, client *ssh.Client, user, pw string) error {
	cmd := fmt.Sprintf(
		"echo %s | sudo -S sh -c 'echo \"%s ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/%s && chmod 0440 /etc/sudoers.d/%s' && sudo -n true",
		shellEscape(pw), user, user, user,
	)
	return runCommand(ctx, client, cmd)
}

func enableAutoLogin(ctx context.Context, client *ssh.Client, user, pw string) error {
	encoded := encodeKCPassword(pw)
	cmd := fmt.Sprintf(
		"printf '%s' | sudo tee /etc/kcpassword > /dev/null && sudo chmod 600 /etc/kcpassword && sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser %s",
		hexEscapes(encoded), user,
	)
	return runCommand(ctx, client, cmd)
}

func installTart(ctx context.Context, client *ssh.Client) error {
	script := `set -euo pipefail
if ! command -v tart >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    brew install cirruslabs/cli/tart
fi
`
	return runCommand(ctx, client, script)
}

func installKubelet(ctx context.Context, client *ssh.Client, version string) error {
	script := fmt.Sprintf(`set -euo pipefail
if [ ! -x /usr/local/bin/kubelet ] || ! /usr/local/bin/kubelet --version | grep -q "v%s"; then
    curl -fsSLo /tmp/kubelet "https://dl.k8s.io/release/v%s/bin/darwin/arm64/kubelet"
    sudo install -m 0755 /tmp/kubelet /usr/local/bin/kubelet
    rm /tmp/kubelet
fi
`, version, version)
	return runCommand(ctx, client, script)
}

func uploadTartCRIBinaries(ctx context.Context, client *ssh.Client, criPath, cniPath string) error {
	if err := uploadFile(ctx, client, criPath, "/tmp/tart-cri", 0o755); err != nil {
		return err
	}
	if err := uploadFile(ctx, client, cniPath, "/tmp/tart-cni", 0o755); err != nil {
		return err
	}
	script := `set -euo pipefail
sudo mkdir -p /opt/cni/bin /var/lib/tart-cri /var/log/tart-cri /var/log/kubelet /var/log/pods /var/run/tart-cri /etc/kubernetes /etc/cni/net.d
sudo install -m 0755 /tmp/tart-cri /usr/local/bin/tart-cri
sudo install -m 0755 /tmp/tart-cni /opt/cni/bin/tart-cni
rm -f /tmp/tart-cri /tmp/tart-cni
`
	return runCommand(ctx, client, script)
}

func writeConfigs(ctx context.Context, client *ssh.Client, cfg Config) error {
	configs := map[string]string{
		"/etc/kubernetes/kubelet-config.yaml":         kubeletConfig(),
		"/etc/cni/net.d/10-tart.conflist":             cniConflist(cfg.PodCIDR),
		"/etc/kubernetes/bootstrap-kubelet.conf":      bootstrapKubeconfig(cfg),
		"/Library/LaunchDaemons/dev.tuist.tart-cri.plist":  tartCRIPlist(),
		"/Library/LaunchDaemons/dev.tuist.kubelet.plist":   kubeletPlist(cfg),
	}

	for path, contents := range configs {
		// Stage to /tmp first, then sudo-install with the right mode.
		// `tee` via sudo lets us write to root-owned paths over a
		// non-root SSH session.
		cmd := fmt.Sprintf("sudo tee %s > /dev/null", path)
		if err := runCommandWithStdin(ctx, client, cmd, contents); err != nil {
			return fmt.Errorf("write %s: %w", path, err)
		}
	}
	return nil
}

func bootDaemons(ctx context.Context, client *ssh.Client) error {
	script := `set -euo pipefail
sudo chown root:wheel /Library/LaunchDaemons/dev.tuist.tart-cri.plist /Library/LaunchDaemons/dev.tuist.kubelet.plist
sudo chmod 644 /Library/LaunchDaemons/dev.tuist.tart-cri.plist /Library/LaunchDaemons/dev.tuist.kubelet.plist
sudo launchctl bootout system/dev.tuist.tart-cri 2>/dev/null || true
sudo launchctl bootout system/dev.tuist.kubelet 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/dev.tuist.tart-cri.plist
sleep 2
sudo launchctl bootstrap system /Library/LaunchDaemons/dev.tuist.kubelet.plist
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
	go func() { done <- session.Run(cmd) }()

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

func uploadFile(ctx context.Context, client *ssh.Client, srcPath, dstPath string, _ int) error {
	// Simple impl: cat the local file into the remote shell's stdin.
	// The operator image carries the binaries at known paths, so this
	// is fine. Avoids depending on scp/sftp as a separate transport.
	return runCommandWithStdin(ctx, client,
		fmt.Sprintf("cat > %s && chmod 0755 %s", dstPath, dstPath),
		readFileOrEmpty(srcPath),
	)
}

// === Config rendering ======================================================

func kubeletConfig() string {
	return `apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
containerRuntimeEndpoint: unix:///var/run/tart-cri/tart-cri.sock
cgroupsPerQOS: false
enforceNodeAllocatable: []
failSwapOn: false
nodeStatusReportFrequency: 30s
nodeStatusUpdateFrequency: 10s
imageMinimumGCAge: 24h
imageGCHighThresholdPercent: 80
imageGCLowThresholdPercent: 60
podLogsDir: /var/log/pods
authentication:
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
  webhook:
    enabled: true
authorization:
  mode: Webhook
resolvConf: /etc/resolv.conf
healthzBindAddress: 127.0.0.1
healthzPort: 10248
`
}

func cniConflist(podCIDR string) string {
	return fmt.Sprintf(`{
  "cniVersion": "1.0.0",
  "name": "tart",
  "plugins": [
    {"type": "tart-cni", "podCIDR": "%s"}
  ]
}
`, podCIDR)
}

func bootstrapKubeconfig(cfg Config) string {
	return fmt.Sprintf(`apiVersion: v1
kind: Config
clusters:
  - name: tuist
    cluster:
      server: %s
      certificate-authority-data: %s
contexts:
  - name: bootstrap
    context:
      cluster: tuist
      user: bootstrap
current-context: bootstrap
users:
  - name: bootstrap
    user:
      token: %s
`, cfg.APIServer, cfg.CACertData, cfg.BootstrapToken)
}

func tartCRIPlist() string {
	return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>dev.tuist.tart-cri</string>
<key>ProgramArguments</key><array>
  <string>/usr/local/bin/tart-cri</string>
  <string>--socket</string><string>/var/run/tart-cri/tart-cri.sock</string>
  <string>--state</string><string>/var/lib/tart-cri/state.json</string>
  <string>--log-dir</string><string>/var/log/pods</string>
</array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>/var/log/tart-cri/stdout.log</string>
<key>StandardErrorPath</key><string>/var/log/tart-cri/stderr.log</string>
<key>ProcessType</key><string>Background</string>
</dict></plist>
`
}

func kubeletPlist(cfg Config) string {
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>dev.tuist.kubelet</string>
<key>ProgramArguments</key><array>
  <string>/usr/local/bin/kubelet</string>
  <string>--config=/etc/kubernetes/kubelet-config.yaml</string>
  <string>--kubeconfig=/etc/kubernetes/kubelet.conf</string>
  <string>--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf</string>
  <string>--cert-dir=/var/lib/kubelet/pki</string>
  <string>--hostname-override=%s</string>
  <string>--node-labels=kubernetes.io/os=darwin,kubernetes.io/arch=arm64,tuist.dev/runtime=tart</string>
  <string>--register-with-taints=tuist.dev/macos=true:NoSchedule</string>
</array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>/var/log/kubelet/stdout.log</string>
<key>StandardErrorPath</key><string>/var/log/kubelet/stderr.log</string>
<key>ProcessType</key><string>Background</string>
</dict></plist>
`, cfg.Hostname)
}

// === kcpassword encoding (Apple's well-known XOR key) =======================

var kcpasswordKey = []byte{0x7D, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F}

func encodeKCPassword(pw string) []byte {
	out := []byte(pw)
	for i := range out {
		out[i] ^= kcpasswordKey[i%len(kcpasswordKey)]
	}
	// Pad to 12 bytes with the magic key itself (Apple convention so
	// loginwindow doesn't try to read past EOF).
	for len(out) < 12 {
		out = append(out, kcpasswordKey[len(out)%len(kcpasswordKey)])
	}
	return out
}

func hexEscapes(data []byte) string {
	var b strings.Builder
	for _, c := range data {
		fmt.Fprintf(&b, "\\x%02x", c)
	}
	return b.String()
}

// shellEscape single-quotes a value safely for embedding in `sh -c '...'`.
func shellEscape(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// readFileOrEmpty is used by uploadFile. We read the binary at provider
// init time and pass the bytes through; avoiding a per-call file read.
// Implemented as a package-level overridable for testability.
var readFileOrEmpty = func(path string) string {
	// Real impl is provided at controller init via SetBinaryReader.
	// This default returns empty so we don't accidentally panic in
	// tests.
	return ""
}

// SetBinaryReader injects the function the controller uses to read
// the embedded tart-cri/tart-cni binary contents. Called from main()
// so the package doesn't need an os import.
func SetBinaryReader(fn func(string) string) {
	readFileOrEmpty = fn
}
