// Package main is the bootstrap CLI for a fresh bare-metal
// vm-image-builder Mac mini. The operator orders a Scaleway Apple
// Silicon M2-L with the macOS-with-Xcode preinstalled image, registers
// their SSH public key in Scaleway IAM, then runs this CLI to turn
// the freshly-booted host into a working GitHub Actions self-hosted
// runner on the [self-hosted, macos, bare-metal, vm-image-builder]
// label set.
//
// Steps, in order, idempotent on retry:
//
//  1. Wait for SSH to come up; capture host key (TOFU) or verify
//     against the operator-supplied SHA256 fingerprint.
//  2. Passwordless sudoers (m1 ALL=(ALL) NOPASSWD: ALL).
//  3. macOS auto-login (kcpassword + autoLoginUser). Required because
//     Tart's Virtualization.framework refuses to start a guest
//     without a live Aqua console session.
//  4. Disable idle sleep / display sleep / lock screen, same reason:
//     the GUI session must stay alive for the next `tart run`.
//  5. Set the macOS hostname so `Runner name:` in the workflow logs
//     identifies the host.
//  6. Install Homebrew (NONINTERACTIVE), tap cirruslabs/cli, install
//     Tart, Packer, mise.
//  7. Verify Xcode is present (the xcresult-processor image build
//     runs `swift build -c release` on the host; Command Line Tools
//     are not sufficient).
//  8. Persist TUIST_MIX_BUILD_ROOT in /etc/zshenv so the
//     xcresult-processor workflow shares a BEAM build cache across
//     runs. /etc/zshenv (not ~/.zprofile) is sourced by every zsh,
//     including the non-login non-interactive shells GitHub Actions
//     launches per step.
//  9. Download the actions/runner tarball, `config.sh` it with the
//     operator-supplied registration token, install + start as a
//     macOS LaunchAgent under m1.
//
// Steps 1–5 are re-used from infra/macos-host-bootstrap (the same
// substrate the Scaleway CAPI controller runs on cluster nodes); 6–9
// are builder-specific.
package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"strings"

	common "github.com/tuist/tuist/infra/macos-host-bootstrap"
	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
)

// DefaultRunnerVersion mirrors infra/runner-image/runner.pkr.hcl's
// `variable "runner_version"` default. Bumping it should track the
// pin there: the same actions/runner version runs on the bare-metal
// host (image bake host) and inside the runner VMs that the image
// produces. Renovate keeps both pins synchronised via the
// `datasource=github-releases depName=actions/runner` marker in
// runner.pkr.hcl; mirror the bump here when that PR opens.
const DefaultRunnerVersion = "2.334.0"

// DefaultRunnerLabels matches `runs-on:` in
// .github/workflows/runner-image.yml and
// .github/workflows/xcresult-processor-image.yml. Drift here is what
// makes the new host invisible to the GitHub scheduler. Keep the
// list in lockstep with the workflow files.
const DefaultRunnerLabels = "self-hosted,macos,bare-metal,vm-image-builder"

// DefaultTuistMixBuildRoot is read by xcresult-processor-image.yml
// (and release.yml's release-xcresult-processor job) to share a
// single _build directory across consecutive jobs on the same host.
// /opt/ is outside m1's $HOME so a stray `rm -rf ~` in a runner job
// can't blow it away.
const DefaultTuistMixBuildRoot = "/opt/tuist-build-cache"

// Config drives the bootstrap.
type Config struct {
	// IP is the public IPv4 Scaleway assigns at order time.
	IP string

	// SSHUser is m1 by default for Scaleway Apple Silicon hosts.
	SSHUser string

	// UserPassword is the SSH user's password, surfaced once by
	// Scaleway at order time. Used for two macOS-specific bootstrap
	// steps (passwordless-sudoers entry + /etc/kcpassword for
	// auto-login) and nothing else. Empty is allowed: the
	// upstream helpers' idempotency-only path skips the password-
	// consuming steps if the artefacts they install (sudoers file,
	// kcpassword) already exist, so a re-run after Scaleway has
	// rotated the password still completes.
	UserPassword string

	// SSHPrivateKey is the PEM-encoded private key matching the
	// public key registered with Scaleway IAM. Scaleway preloads the
	// IAM public key into m1's authorized_keys at order time, so the
	// first SSH dial works without password auth.
	//
	// Mutually exclusive with UseSSHAgent: exactly one auth source
	// must be set.
	SSHPrivateKey []byte

	// UseSSHAgent, when true, sources signers from $SSH_AUTH_SOCK
	// instead of an in-process private key. The recommended path when
	// the fleet keypair lives in 1Password: enable the SSH Key item
	// for 1Password's SSH agent in the GUI, set SSH_AUTH_SOCK to
	// 1Password's agent socket, and run with --use-ssh-agent. The
	// private key bytes never touch the operator's filesystem.
	UseSSHAgent bool

	// Hostname is set via scutil. Convention:
	// `vm-image-builder-<n>` for the nth host.
	Hostname string

	// KnownHostFingerprint, when set, is the SHA256 fingerprint the
	// dial verifies against. Empty on first run; the returned value
	// is what the operator records in 1Password for next time.
	KnownHostFingerprint string

	// TuistMixBuildRoot defaults to DefaultTuistMixBuildRoot.
	TuistMixBuildRoot string

	// GHOrg is the GitHub organization to register the runner
	// against, e.g. "tuist". The runner is registered at organization
	// scope (not repository scope) so the shared fleet can serve any
	// repo in the org without re-registration per repo.
	GHOrg string

	// GHToken is the short-lived registration token minted via
	//   gh api -X POST /orgs/<org>/actions/runners/registration-token --jq .token
	// Tokens have ~1h TTL; mint immediately before running this CLI.
	GHToken string

	// RunnerName defaults to Hostname.
	RunnerName string

	// RunnerLabels defaults to DefaultRunnerLabels.
	RunnerLabels string

	// RunnerVersion defaults to DefaultRunnerVersion.
	RunnerVersion string

	// LogOut receives streamed stdout/stderr from long-running
	// remote commands (brew install, runner config). Defaults to
	// io.Discard if nil; the CLI sets it to os.Stderr.
	LogOut io.Writer
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
	if err := cfg.validate(); err != nil {
		return "", err
	}
	cfg.applyDefaults()

	auth, agentCloser, err := buildAuth(cfg)
	if err != nil {
		return "", err
	}
	if agentCloser != nil {
		defer agentCloser.Close()
	}

	hk := common.NewHostKeyState(cfg.KnownHostFingerprint)

	if err := common.WaitForSSHAuth(ctx, cfg.IP, cfg.SSHUser, auth, hk); err != nil {
		return "", err
	}
	client, err := common.DialAuth(cfg.IP, cfg.SSHUser, auth, hk)
	if err != nil {
		return "", err
	}
	defer client.Close()

	if err := common.EnablePasswordlessSudo(ctx, client, cfg.SSHUser, cfg.UserPassword); err != nil {
		return hk.Observed(), fmt.Errorf("passwordless sudo: %w", err)
	}
	if err := common.EnableAutoLogin(ctx, client, cfg.SSHUser, cfg.UserPassword); err != nil {
		return hk.Observed(), fmt.Errorf("auto-login: %w", err)
	}
	if err := common.DisableIdleSleep(ctx, client); err != nil {
		return hk.Observed(), fmt.Errorf("disable idle sleep: %w", err)
	}
	if err := common.SetHostname(ctx, client, cfg.Hostname); err != nil {
		return hk.Observed(), fmt.Errorf("set hostname: %w", err)
	}
	if err := installHomebrew(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("install homebrew: %w", err)
	}
	if err := installBrewPackages(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("install brew packages: %w", err)
	}
	if err := verifyXcode(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("verify xcode: %w", err)
	}
	if err := writeBuildCacheEnv(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("write build cache env: %w", err)
	}
	if err := installActionsRunner(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("install gh actions runner: %w", err)
	}
	return hk.Observed(), nil
}

func (cfg *Config) validate() error {
	missing := []string{}
	if cfg.IP == "" {
		missing = append(missing, "IP")
	}
	if cfg.SSHUser == "" {
		missing = append(missing, "SSHUser")
	}
	if cfg.Hostname == "" {
		missing = append(missing, "Hostname")
	}
	if cfg.GHOrg == "" {
		missing = append(missing, "GHOrg")
	}
	if cfg.GHToken == "" {
		missing = append(missing, "GHToken")
	}
	if len(missing) > 0 {
		return fmt.Errorf("missing required config: %s", strings.Join(missing, ", "))
	}
	switch {
	case cfg.UseSSHAgent && len(cfg.SSHPrivateKey) > 0:
		return fmt.Errorf("SSHPrivateKey and UseSSHAgent are mutually exclusive")
	case !cfg.UseSSHAgent && len(cfg.SSHPrivateKey) == 0:
		return fmt.Errorf("one of SSHPrivateKey / UseSSHAgent is required")
	}
	return nil
}

// buildAuth turns Config.SSHPrivateKey / Config.UseSSHAgent into the
// ssh.AuthMethod list to hand to DialAuth. Returns a closer for the
// SSH agent socket (or nil when using in-process keys); the caller
// defers Close to avoid leaking the unix-socket fd across long-running
// dials.
func buildAuth(cfg Config) ([]ssh.AuthMethod, io.Closer, error) {
	if cfg.UseSSHAgent {
		sock := os.Getenv("SSH_AUTH_SOCK")
		if sock == "" {
			return nil, nil, fmt.Errorf("--use-ssh-agent set but SSH_AUTH_SOCK is empty; enable 1Password's SSH agent and re-run")
		}
		conn, err := net.Dial("unix", sock)
		if err != nil {
			return nil, nil, fmt.Errorf("dial ssh agent at %s: %w", sock, err)
		}
		ag := agent.NewClient(conn)
		return []ssh.AuthMethod{ssh.PublicKeysCallback(ag.Signers)}, conn, nil
	}
	signer, err := ssh.ParsePrivateKey(cfg.SSHPrivateKey)
	if err != nil {
		return nil, nil, fmt.Errorf("parse ssh key: %w", err)
	}
	return []ssh.AuthMethod{ssh.PublicKeys(signer)}, nil, nil
}

func (cfg *Config) applyDefaults() {
	if cfg.TuistMixBuildRoot == "" {
		cfg.TuistMixBuildRoot = DefaultTuistMixBuildRoot
	}
	if cfg.RunnerName == "" {
		cfg.RunnerName = cfg.Hostname
	}
	if cfg.RunnerLabels == "" {
		cfg.RunnerLabels = DefaultRunnerLabels
	}
	if cfg.RunnerVersion == "" {
		cfg.RunnerVersion = DefaultRunnerVersion
	}
}

// installHomebrew installs Homebrew non-interactively on a fresh host.
// Idempotent: detects an existing install via `command -v brew` and
// returns early. The shellenv eval line in ~/.zprofile keeps brew on
// PATH for subsequent SSH sessions; we also export it for the current
// session's later steps in the same script.
func installHomebrew(ctx context.Context, client *ssh.Client, cfg Config) error {
	const script = `set -euo pipefail
if command -v brew >/dev/null 2>&1; then
  echo "brew already installed at $(command -v brew)"
  exit 0
fi
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
if ! grep -q '/opt/homebrew/bin/brew shellenv' ~/.zprofile 2>/dev/null; then
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
fi
`
	return runStreaming(ctx, client, script, "homebrew", cfg.LogOut)
}

// installBrewPackages installs Tart, Packer, and mise. The image
// workflows themselves run `brew upgrade tart` on every job so the
// host's Tart version tracks upstream automatically; this step just
// gets the formula present so the first job has something to upgrade.
//
// mise is required because jdx/mise-action shells out to a mise
// binary already on PATH. Packer drives the Tart image bake.
//
// Taps:
//   - cirruslabs/cli hosts the Tart formula.
//   - hashicorp/tap hosts Packer. HashiCorp pulled Packer (and the
//     rest of the BSL-licensed tools) from Homebrew core when they
//     relicensed, so `brew install packer` now fails with
//     "No available formula". The tap is the supported install path.
func installBrewPackages(ctx context.Context, client *ssh.Client, cfg Config) error {
	const script = `set -euo pipefail
eval "$(/opt/homebrew/bin/brew shellenv)"
brew tap cirruslabs/cli
brew tap hashicorp/tap
brew install mise tart hashicorp/tap/packer
brew --version
tart --version
packer --version
mise --version
`
	return runStreaming(ctx, client, script, "brew-install", cfg.LogOut)
}

// verifyXcode confirms a full Xcode is installed (not just Command
// Line Tools) and the license has been accepted. The
// xcresult-processor image build runs the Swift xcresult NIF's
// `swift build -c release` on the host, which fails against CLT
// because of macOS SDK availability. The expected provisioning shape
// is the Scaleway "macOS + Xcode" preinstalled image; this step
// short-circuits with a clear error when the operator ordered the
// vanilla macOS image by accident.
func verifyXcode(ctx context.Context, client *ssh.Client, cfg Config) error {
	const script = `set -euo pipefail
if [ ! -d /Applications/Xcode.app/Contents/Developer ]; then
  echo "ERROR: /Applications/Xcode.app is missing on this host." >&2
  echo "  The xcresult-processor image build needs a full Xcode (not CLT)." >&2
  echo "  Reorder the Mac mini with the Scaleway 'macOS + Xcode' preinstalled image," >&2
  echo "  or install Xcode via the App Store before re-running this bootstrap." >&2
  exit 1
fi
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
if ! sudo xcodebuild -license check >/dev/null 2>&1; then
  sudo xcodebuild -license accept
fi
xcrun --find swift >/dev/null
echo "Xcode OK: $(xcodebuild -version | head -n1)"
`
	return runStreaming(ctx, client, script, "verify-xcode", cfg.LogOut)
}

// writeBuildCacheEnv exports TUIST_MIX_BUILD_ROOT in /etc/zshenv.
// /etc/zshenv is the only zsh init file sourced by *every* zsh
// invocation, including non-login non-interactive shells. The runner's
// per-step shells fall into that category, so ~/.zprofile (login only)
// and ~/.zshrc (interactive only) would both miss them.
//
// Idempotent via a grep-then-append guard so re-runs don't duplicate
// the line. The cache directory is created with m1 ownership so the
// runner's mix invocations can write to it without sudo.
func writeBuildCacheEnv(ctx context.Context, client *ssh.Client, cfg Config) error {
	script := fmt.Sprintf(`set -euo pipefail
sudo mkdir -p %[1]s
sudo chown %[2]s:staff %[1]s
LINE='export TUIST_MIX_BUILD_ROOT=%[1]s'
if ! sudo grep -qxF "$LINE" /etc/zshenv 2>/dev/null; then
  echo "$LINE" | sudo tee -a /etc/zshenv > /dev/null
fi
`, shellQuote(cfg.TuistMixBuildRoot), shellQuote(cfg.SSHUser))
	return runStreaming(ctx, client, script, "build-cache-env", cfg.LogOut)
}

// installActionsRunner downloads the actions/runner tarball into
// /opt/actions-runner (m1-owned so config.sh can write its state
// files), configures it for cfg.GHOrg with the operator-supplied
// short-lived registration token, and installs it as a launchd
// LaunchAgent under m1.
//
// `./svc.sh install m1` on macOS writes
// ~m1/Library/LaunchAgents/actions.runner.<repo>.<name>.plist and
// loads it into m1's GUI session. The auto-login configured earlier
// is what makes that GUI session exist at boot, which is what loads
// the agent after a reboot. Without auto-login the runner would only
// come up when someone manually logged in to the host.
//
// --replace lets re-runs swap the existing registration of the same
// name, which is the path we take when re-bootstrapping the same
// host after a config change.
func installActionsRunner(ctx context.Context, client *ssh.Client, cfg Config) error {
	script := fmt.Sprintf(`set -euo pipefail
RUNNER_DIR=/opt/actions-runner
RUNNER_VERSION=%[1]s
TARBALL=actions-runner-osx-arm64-${RUNNER_VERSION}.tar.gz
URL=https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}

sudo mkdir -p "$RUNNER_DIR"
sudo chown %[2]s:staff "$RUNNER_DIR"

if [ ! -f "$RUNNER_DIR/config.sh" ]; then
  curl -fsSL -o "/tmp/${TARBALL}" "$URL"
  tar -xzf "/tmp/${TARBALL}" -C "$RUNNER_DIR"
  rm -f "/tmp/${TARBALL}"
fi

cd "$RUNNER_DIR"
# Stop any existing service first; we need a quiescent agent before
# ./config.sh tries to swap registrations.
./svc.sh stop 2>/dev/null || true
./svc.sh uninstall 2>/dev/null || true

# When re-registering an already-configured runner, ./config.sh will
# refuse with "A runner exists with the same name" unless we pre-clear
# its local state. The clean shape is "./config.sh remove", but that
# needs a removal token; we drop the .runner / .credentials files
# directly so the next ./config.sh sees a fresh checkout. The
# server-side registration of the previous runner is the operator's
# job to clean up (gh api -X DELETE /orgs/<org>/actions/runners/<id>);
# we don't want to do it implicitly because the previous runner may
# legitimately exist with the same name (e.g. mid-rotation).
rm -f .runner .credentials .credentials_rsaparams

./config.sh \
  --url https://github.com/%[3]s \
  --token %[4]s \
  --name %[5]s \
  --labels %[6]s \
  --work _work \
  --unattended \
  --replace
./svc.sh install %[2]s
./svc.sh start
./svc.sh status
`,
		shellQuote(cfg.RunnerVersion),
		shellQuote(cfg.SSHUser),
		shellQuote(cfg.GHOrg),
		shellQuote(cfg.GHToken),
		shellQuote(cfg.RunnerName),
		shellQuote(cfg.RunnerLabels),
	)
	return runStreaming(ctx, client, script, "actions-runner", cfg.LogOut)
}

// runStreaming wraps the SSH session so brew install and runner
// config don't hang silently for minutes. Each remote stdout/stderr
// line is prefixed with `[step]` so the operator can tell which
// bootstrap stage is currently making progress.
func runStreaming(ctx context.Context, client *ssh.Client, script, step string, out io.Writer) error {
	if out == nil {
		out = io.Discard
	}
	session, err := client.NewSession()
	if err != nil {
		return err
	}
	defer session.Close()

	prefix := []byte("[" + step + "] ")
	pw := &prefixWriter{w: out, prefix: prefix}
	session.Stdout = pw
	var stderr bytes.Buffer
	session.Stderr = io.MultiWriter(pw, &stderr)

	done := make(chan error, 1)
	go func() { done <- session.Run(script) }()
	select {
	case <-ctx.Done():
		_ = session.Signal(ssh.SIGTERM)
		return ctx.Err()
	case err := <-done:
		if err != nil {
			return fmt.Errorf("ssh exec: %w (stderr tail: %s)", err, tailLines(stderr.String(), 20))
		}
		return nil
	}
}

// prefixWriter prepends a per-step tag to each line streamed back
// from the remote shell. Buffers across writes so a `\n`-split tag
// doesn't drop into the middle of a remote log line.
type prefixWriter struct {
	w      io.Writer
	prefix []byte
	buf    bytes.Buffer
}

func (p *prefixWriter) Write(b []byte) (int, error) {
	p.buf.Write(b)
	for {
		line, err := p.buf.ReadBytes('\n')
		if err != nil {
			// Incomplete line: push it back for the next write.
			p.buf.Reset()
			p.buf.Write(line)
			return len(b), nil
		}
		if _, err := p.w.Write(p.prefix); err != nil {
			return len(b), err
		}
		if _, err := p.w.Write(line); err != nil {
			return len(b), err
		}
	}
}

func tailLines(s string, n int) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(lines) <= n {
		return strings.Join(lines, "\n")
	}
	return strings.Join(lines[len(lines)-n:], "\n")
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
