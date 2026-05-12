// Package bootstrap turns a freshly-provisioned macOS host into a
// tart-kubelet-ready cluster Node.
//
// Provider-agnostic by design: the caller fills in a Config and Run
// does the rest. Anything host-shaped (IP, SSH credentials, the
// SSH user's password used for passwordless-sudoers and
// /etc/kcpassword, the TOFU host-key pin) is an input; everything
// macOS-shaped is the same on every host:
//   - Auto-login (Virtualization.framework requires a live console).
//   - Hostname = CR name (so tart-kubelet's default --node-name
//     lines up with the inventory resource).
//   - Tart install (the caller-supplied tart.app tarball pinned in
//     the operator image is extracted to /usr/local/lib/tart.app
//     with a /usr/local/bin/tart wrapper).
//   - Kubeconfig drop + tart-kubelet binary upload + launchd plist.
//
// Steps, in order, idempotent on retry:
//  1. Wait for SSH (host has just booted from the provider's image).
//  2. Grant the SSH user passwordless sudo using UserPassword.
//  3. Configure GUI auto-login via /etc/kcpassword + autoLoginUser
//     so Virtualization.framework has a live console session.
//  4. Set the macOS hostname to NodeName.
//  5. Install Tart by extracting the operator-pinned tart.app tarball
//     to /usr/local/lib/tart.app + wrapper at /usr/local/bin/tart.
//  6. Drop the kubeconfig the controller built for this host.
//  7. Upload the tart-kubelet binary.
//  8. Write the launchd plist with this host's flags + load it.
//
// After step 8 the agent on the host registers a Node and starts
// reconciling Pods. The provider's MachineReconciler flips
// Machine.Status.Ready when this returns nil.
package bootstrap

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"net"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"
)

// Config drives the bootstrap.
type Config struct {
	IP      string
	SSHUser string

	// UserPassword is the SSH user's password. Used for two
	// macOS-specific bootstrap steps (passwordless-sudoers entry
	// + /etc/kcpassword for auto-login) and nothing else; the
	// caller is responsible for obtaining it.
	UserPassword string

	SSHPrivateKey []byte

	// NodeName is the cluster Node name tart-kubelet should register.
	// Typically matches the CAPI Machine CR name so `kubectl get
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

	// TartTarball is the gzipped tar of the upstream `tart.app` bundle
	// (the asset published as `tart.tar.gz` on each cirruslabs/tart
	// GitHub release), baked into the operator image at build time and
	// read at startup. We ship the whole `.app` rather than the bare
	// executable inside it because Tart's signature + Virtualization.
	// framework entitlements live on the bundle, not the binary alone.
	// Pinning the version in the operator image makes the Tart version
	// reproducible across reboots and re-provisions; bumping it is a
	// deliberate Dockerfile change.
	TartTarball []byte

	// HostCPU / HostMemoryMB / MaxPods are advertised on the Node.
	HostCPU      int
	HostMemoryMB int
	MaxPods      int

	// NodeLabels is the set of labels tart-kubelet stamps on the
	// Node it registers. The bootstrap layer is generic — fleet
	// membership is just one entry the caller adds (typically
	// `{"tuist.dev/fleet": <fleetName>}`). Empty map omits the
	// flag entirely; the Node carries no operator-set labels.
	//
	// Why bootstrap-time and not a post-registration patch: the
	// label has to land atomically with kubelet registration, or
	// there's a race window where a Node is `Ready` but unlabeled
	// and Pods with `nodeSelector: tuist.dev/fleet=<name>` fail to
	// schedule on it. Same convention CAPI bootstrap providers
	// follow with `kubeadm`'s `kubeletExtraArgs.node-labels`.
	NodeLabels map[string]string

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

	if err := enablePasswordlessSudo(ctx, client, cfg.SSHUser, cfg.UserPassword); err != nil {
		return hk.observed(), fmt.Errorf("passwordless sudo: %w", err)
	}
	if err := enableAutoLogin(ctx, client, cfg.SSHUser, cfg.UserPassword); err != nil {
		return hk.observed(), fmt.Errorf("auto-login: %w", err)
	}
	if err := disableIdleSleep(ctx, client); err != nil {
		return hk.observed(), fmt.Errorf("disable idle sleep: %w", err)
	}
	if cfg.NodeName != "" {
		if err := setHostname(ctx, client, cfg.NodeName); err != nil {
			return hk.observed(), fmt.Errorf("set hostname: %w", err)
		}
	}
	if err := installTart(ctx, client, cfg.TartTarball); err != nil {
		return hk.observed(), fmt.Errorf("install tart: %w", err)
	}
	if err := installVMEgressFirewall(ctx, client); err != nil {
		return hk.observed(), fmt.Errorf("install vm egress firewall: %w", err)
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
		// Apple's macOS SLA caps virtualized macOS instances at 2 per
		// bare-metal host (Tart refuses to start a third VM). max-pods
		// is set to 3 (not 2) because it counts every Pod on the Node,
		// not just Tart-VM Pods — host-system DaemonSets like
		// hcloud-csi-node already consume one slot, and the rolling-
		// update surge needs a third for csi(1) + old(1) + new(1).
		// The 2-VM cap is enforced by Tart at the virtualization layer.
		maxPods = 3
	}
	user := cfg.SSHUser
	if user == "" {
		user = "m1"
	}
	// `--node-labels` is rendered conditionally so a host bootstrapped
	// without any labels (or one whose operator wants to retire
	// labels) renders an identical plist. tart-kubelet treats an
	// absent flag as "operator-managed labels = ∅" and drops any
	// labels it previously set, giving us a clean retire path.
	//
	// k=v,k=v,... form (kubelet's --node-labels convention).
	// Sorted for deterministic plist rendering — otherwise map
	// iteration order would dirty the host fingerprint and
	// trigger needless plist rewrites.
	nodeLabelsArg := ""
	if len(cfg.NodeLabels) > 0 {
		keys := make([]string, 0, len(cfg.NodeLabels))
		for k := range cfg.NodeLabels {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		pairs := make([]string, 0, len(keys))
		for _, k := range keys {
			pairs = append(pairs, fmt.Sprintf("%s=%s", k, cfg.NodeLabels[k]))
		}
		nodeLabelsArg = fmt.Sprintf("\n    <string>--node-labels=%s</string>", strings.Join(pairs, ","))
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
    <string>--max-pods=%[4]d</string>%[6]s
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
`, cfg.NodeName, cpu, mem, maxPods, user, nodeLabelsArg)
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
// authenticate the initial sudo with the SSH user's password supplied
// by the caller; subsequent sudo calls don't need it.
//
// Pre-ordered hosts that sat in the pool longer than Scaleway's
// password-disclosure window won't have a usable password — for those
// the operator is expected to seed /etc/sudoers.d/<user>-nopasswd by
// hand via the prep script's VNC instructions; the existence check
// at the top of the script makes this branch a no-op when that's
// already been done.
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
	// No password to XOR into /etc/kcpassword means we'd write a
	// broken kcpassword (just the cipher key with no plaintext under
	// it) and macOS would silently fail to auto-login the user. That
	// path is hit on adopted pool hosts where Scaleway no longer
	// surfaces the bootstrap password; the operator is expected to
	// stage `/etc/kcpassword` + autoLoginUser by hand as part of the
	// prep-script flow. Bail before doing damage.
	if password == "" {
		return nil
	}
	encoded := encodeKCPassword(password)
	// Stage the binary kcpassword via base64 to avoid TTY issues.
	//
	// Why we kick loginwindow at the end:
	// On headless Apple Silicon Mac minis (Scaleway, AWS EC2 Mac, etc.)
	// macOS's loginwindow at boot does NOT honor the auto-login
	// preference unless a display device is attached — so the system
	// boots, the console stays at the root user, and no Aqua (GUI)
	// session for the auto-login user comes up. Apple's
	// Virtualization.framework refuses to start macOS guests in that
	// state ("Failed to get current host key" / VZErrorDomain Code=-9),
	// which means tart-kubelet's `tart run` fails on every pod even
	// after Tart and the kubelet are correctly installed.
	//
	// Killing loginwindow with SIGHUP forces it to respawn, and the
	// respawned process — unlike the boot-time process — does honor
	// the auto-login preference, brings up the Aqua session, and the
	// bridge100 vmnet interface starts working. Idempotent: if the
	// Aqua session already exists, the kick still works (loginwindow
	// re-establishes it cleanly) and we accept that small cost over
	// branching on session state.
	script := fmt.Sprintf(`set -euo pipefail
echo '%[2]s' | base64 -d | sudo tee /etc/kcpassword > /dev/null
sudo chmod 600 /etc/kcpassword
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser '%[1]s'
sudo killall -HUP loginwindow 2>/dev/null || true
# Wait for the Aqua session to come up. loginwindow respawn typically
# takes <2s; 30s is generous. If it still doesn't appear we let
# bootstrap continue — Stage 2 of reconcileNormal will retry on the
# next reconcile if VZ subsequently rejects the VM start.
for i in $(seq 1 30); do
  if sudo launchctl print "gui/$(id -u '%[1]s')" 2>/dev/null | grep -q 'session = Aqua'; then
    exit 0
  fi
  sleep 1
done
`, user, encoded)
	return runCommand(ctx, client, script)
}

// disableIdleSleep stops macOS from tearing the user's Aqua session
// down out from under tart-kubelet. Apple's Virtualization framework
// needs the auto-login user to hold a live console session at the
// moment of `tart run`; if the host idle-sleeps, the screensaver
// triggers an auto-logout, or display-sleep flushes WindowServer,
// the session goes away and every subsequent VM start fails with
// `VZErrorDomain Code=-9 / Failed to create new HostKey` until
// something kicks loginwindow again. tart-kubelet has a runtime
// preflight that re-establishes the session on demand, but
// preventing the teardown in the first place avoids the sub-30s
// reanimation latency on every cold-start Pod and keeps the kubelet
// from spamming sudo against loginwindow under load.
//
// Settings applied:
//   - `pmset -a sleep 0 displaysleep 0 disksleep 0`: disable host
//     idle sleep + display blank-out + disk spindown. These are
//     `-a` (all power sources) because Mac mini servers are AC-only
//     but we don't trust the default profile selection.
//   - `com.apple.screensaver idleTime 0`: disable the screensaver.
//     Without this, even with `displaysleep 0`, the screensaver
//     timer fires and (depending on host policy) can trigger
//     auto-logout.
//   - `com.apple.screensaver askForPassword 0`: don't lock the
//     screen. Locking destroys the GUI/Aqua session in the same way
//     a logout does on Tahoe.
//   - `com.apple.autologout.AutoLogOutDelay 0`: disable auto-logout
//     after inactivity. This is the policy Apple uses for managed
//     fleets; off-by-default on consumer Macs but Scaleway-baked
//     macOS images sometimes ship with it on.
//
// Idempotent: every call writes the same values regardless of prior
// state. Failures here are fatal because there's no point shipping
// a host that will silently fall over an hour after bootstrap.
func disableIdleSleep(ctx context.Context, client *ssh.Client) error {
	script := `set -euo pipefail
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
sudo defaults write /Library/Preferences/com.apple.screensaver idleTime -int 0
sudo defaults write /Library/Preferences/com.apple.screensaver askForPassword -int 0
sudo defaults write /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay -int 0
`
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

// installTart unpacks the operator-baked `tart.app` tarball into
// /usr/local/lib/tart.app and writes a /usr/local/bin/tart wrapper
// that execs the binary inside the bundle. Idempotent — overwrites on
// every call, which is fine because the operator image pins the
// version and a re-run on an already-bootstrapped host is rare.
//
// Why a wrapper script instead of a symlink: Tart's
// Virtualization.framework entitlements are scoped to the .app
// bundle's signature, so the executable has to be invoked through its
// bundle path. The wrapper hides that path detail from callers
// (tart-kubelet, operators SSHing in to debug) which all want a
// stable `tart` on PATH.
func installTart(ctx context.Context, client *ssh.Client, tarball []byte) error {
	if len(tarball) == 0 {
		return fmt.Errorf("tart tarball is empty")
	}
	script := `set -euo pipefail
sudo mkdir -p /usr/local/lib /usr/local/bin
sudo rm -rf /usr/local/lib/tart.app
sudo tar -xzf - -C /usr/local/lib
sudo tee /usr/local/bin/tart >/dev/null <<'EOF'
#!/bin/sh
exec /usr/local/lib/tart.app/Contents/MacOS/tart "$@"
EOF
sudo chmod 0755 /usr/local/bin/tart
/usr/local/bin/tart --version
`
	return runCommandWithStdin(ctx, client, script, string(tarball))
}

// installVMEgressFirewall configures pfctl rules that drop egress
// from the host's vmnet bridge to cluster-private destinations
// (RFC1918 ranges) while allowing public-internet egress. Tart
// VMs attach to vmnet (Apple's bridged-NAT networking for
// Virtualization.framework) and inherit IPs in the 192.168.64.0/22
// range; without these rules the customer-controlled workload
// inside the VM can reach the K8s Pod/Service network, other
// Mac minis on the same cluster's host network, and any RFC1918
// peer the host can route to.
//
// The runner-namespace NetworkPolicy explicitly cannot help here:
// vmnet bridges packets onto the host's L2 before they touch the
// CNI's iptables chains, so Pod-level policies never see VM
// traffic. The packet filter on the host is the only enforcement
// point.
//
// What the rules allow:
//   - vmnet→public internet egress (DNS, GitHub API, package
//     registries) — the only thing the runner actually needs.
//   - vmnet→vmnet local subnet (one-VM-per-host today; this is
//     a no-op but avoids accidental breakage if we ever bin-pack).
//
// What the rules block:
//   - vmnet→10.0.0.0/8 (typical Pod/Service CIDRs, K8s control
//     plane, intra-VPC peers).
//   - vmnet→172.16.0.0/12 (alt Pod CIDR space, some VPNs).
//   - vmnet→169.254.0.0/16 (cloud metadata endpoints — VMs must
//     never reach the host's IMDS, that's a credential leak).
//
// Why 192.168.0.0/16 isn't blocked wholesale: vmnet itself is on
// 192.168.x. Blocking the entire /16 would also drop intra-VM
// traffic and SSH from the operator network if that ever lives
// on 192.168. Since cluster CIDRs in production are 10.x, the
// blocklist is precise rather than maximal.
//
// Idempotent: writes the same anchor file on every call. Enables
// pf if not already enabled. The launchd plist re-loads the
// rules on every boot so a reboot doesn't drop the filter.
func installVMEgressFirewall(ctx context.Context, client *ssh.Client) error {
	script := `set -euo pipefail

# Idempotent install of the pf anchor file. The anchor namespaces
# our rules under "tuist.runners" so we don't collide with any
# operator-added entries in /etc/pf.conf.
sudo mkdir -p /etc/pf.anchors
sudo tee /etc/pf.anchors/tuist.runners >/dev/null <<'PFCONF'
# Tuist runner VM egress filter.
#
# vmnet places Tart VMs on 192.168.64.0/22 (Apple's documented
# bridged-NAT range). Block customer-workload egress from those
# source IPs to cluster-private destinations; allow everything
# else (public internet is the workload's actual need).
#
# IMPORTANT: rules are evaluated last-match-wins; the explicit
# block lines run AFTER the default pass via the 'quick' keyword.

table <vm_sources> persist { 192.168.64.0/22 }
table <blocked_dst> persist { 10.0.0.0/8, 172.16.0.0/12, 169.254.0.0/16 }

# Drop VM→private destinations at the host edge.
block drop out quick from <vm_sources> to <blocked_dst>

# Belt-and-suspenders: explicitly block the AWS/cloud metadata
# IP even on hosts where the routing table wouldn't normally
# carry it. A static rule survives any future routing changes
# from the cluster operator.
block drop out quick from <vm_sources> to 169.254.169.254
PFCONF

# Splice the anchor into /etc/pf.conf if it isn't already there.
# /etc/pf.conf is editable per-host (vs. /System/Library which is
# SIP-protected); macOS's default pf.conf carries a marker line
# we anchor our insert against.
if ! sudo grep -q "anchor \"tuist.runners\"" /etc/pf.conf; then
  sudo tee -a /etc/pf.conf >/dev/null <<'PFCONFENTRY'

# Tuist runner VM egress filter — see /etc/pf.anchors/tuist.runners
anchor "tuist.runners"
load anchor "tuist.runners" from "/etc/pf.anchors/tuist.runners"
PFCONFENTRY
fi

# Validate the ruleset before activating. -nf parses without
# loading; if this fails we want a clear bootstrap error rather
# than a half-loaded filter.
sudo pfctl -nf /etc/pf.conf

# Enable pf (no-op if already enabled) and reload the ruleset.
# -E enables and pins the token so a subsequent disable from
# elsewhere doesn't silently drop our rules; -f reloads.
sudo pfctl -E 2>/dev/null || true
sudo pfctl -f /etc/pf.conf

# launchd job to re-arm pf on every boot. macOS doesn't persist
# the -E enable across reboots in all configurations; an
# explicit RunAtLoad agent makes the filter durable.
sudo tee /Library/LaunchDaemons/dev.tuist.pfctl-runners.plist >/dev/null <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.tuist.pfctl-runners</string>
  <key>ProgramArguments</key>
  <array>
    <string>/sbin/pfctl</string>
    <string>-f</string>
    <string>/etc/pf.conf</string>
    <string>-E</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>/var/log/tuist-pfctl-runners.log</string>
</dict>
</plist>
PLIST
sudo chown root:wheel /Library/LaunchDaemons/dev.tuist.pfctl-runners.plist
sudo chmod 0644 /Library/LaunchDaemons/dev.tuist.pfctl-runners.plist
sudo launchctl bootout system/dev.tuist.pfctl-runners 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/dev.tuist.pfctl-runners.plist
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
