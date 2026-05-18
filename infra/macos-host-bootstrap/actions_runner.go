package bootstrap

import (
	"context"
	"fmt"

	"golang.org/x/crypto/ssh"
)

// GHActionsRunnerConfig is the bootstrap-time configuration for
// installing a GitHub Actions self-hosted runner agent on a Mac mini.
//
// The Mac mini's role in the cluster is unaffected: tart-kubelet
// still runs and the host registers as a Kubernetes Node. The
// runner agent is an additional launchd job that picks up image-
// bake workflow jobs from GitHub and runs them on the bare-metal
// host (typically driving `packer build` against the host's own
// Tart daemon). Pods are kept off these hosts via the per-fleet
// `tuist.dev/fleet=<fleet>` NodeLabel; no Pod selects on the
// builder fleet, so kubelet stays idle while the runner agent works.
//
// Set on `Config.GHActionsRunner` when the caller (the CAPI
// reconciler) wants the builder-tooling install + runner-agent
// install appended to the standard Node bootstrap. Leave nil for
// pure Node hosts (the default fleet).
type GHActionsRunnerConfig struct {
	// GHOrg is the GitHub organization to register the runner
	// against. Org-scope so any repo in the org can use the runner
	// without per-repo registration.
	GHOrg string

	// GHRunnerLabels is the comma-separated label set the runner
	// advertises to GitHub. Must include every label the workflows
	// that schedule onto this fleet pin in `runs-on:` (today
	// runner-image.yml and xcresult-processor-image.yml both pin
	// `[self-hosted, macos, bare-metal, vm-image-builder]`).
	GHRunnerLabels string

	// GHRunnerVersion pins the actions/runner release the
	// reconciler downloads onto the host. Keep in sync with
	// `runner_version` in infra/runner-image/runner.pkr.hcl so the
	// runner agent baked into the runner-image guest matches the
	// agent running on the host that bakes that image.
	GHRunnerVersion string

	// GHRunnerRegistrationToken is the short-lived (~1h TTL) token
	// minted via
	//   gh api -X POST /orgs/<org>/actions/runners/registration-token --jq .token
	// or the equivalent GitHub-App-driven mint. The reconciler
	// resolves it from a Secret named in the CR. Tokens expire fast;
	// the operator is responsible for keeping the Secret fresh.
	GHRunnerRegistrationToken string

	// TuistMixBuildRoot exports `TUIST_MIX_BUILD_ROOT=<value>` in
	// /etc/zshenv on the host so the xcresult-processor build
	// workflow shares the BEAM build cache across consecutive jobs.
	TuistMixBuildRoot string
}

// installBuilderTooling lays down the host-level dependencies the
// image-bake workflows expect to find on PATH: Homebrew, mise (the
// jdx/mise-action step shells out to it), Tart from the
// cirruslabs/cli tap (the same one tart-kubelet would use, but the
// workflows expect a brew-managed install they can `brew upgrade`
// before each bake), and Packer from hashicorp/tap.
//
// `hashicorp/tap` instead of Homebrew core because HashiCorp pulled
// Packer (and the rest of the BSL-licensed tools) from core when
// they relicensed; `brew install packer` returns "No available
// formula" now and the tap is the supported install path.
//
// Idempotent across reruns: `brew install` is a no-op when the
// formula is already at the latest version, and the Homebrew
// installer detects an existing install and exits cleanly.
func installBuilderTooling(ctx context.Context, client *ssh.Client) error {
	const script = `set -euo pipefail
if ! command -v brew >/dev/null 2>&1; then
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
brew tap cirruslabs/cli
brew tap hashicorp/tap
brew install mise tart hashicorp/tap/packer

# Pin Tart + Packer so subsequent ` + "`brew upgrade`" + ` calls (whether
# triggered by an operator typing 'brew upgrade' interactively, or by
# a workflow step that called it defensively) are no-ops. Stable
# binary signatures are load-bearing on macOS Tahoe: the Local
# Network access TCC grant is keyed on the binary's code-signature,
# and an upgrade replaces the binary with a new signature, which
# silently revokes the grant. Packer's ` + "`tart-cli.runner: Waiting for SSH`" + `
# then hangs forever because the host can no longer open TCP to the
# guest at 192.168.64.x, and the only way to re-grant is a VNC
# session and a manual "Allow" click. Pinning keeps the grant stable
# across rebuilds; intentional Tart/Packer upgrades become an
# explicit operator action that pairs with re-running the Allow
# click out of band.
brew pin tart packer

tart --version
packer --version
mise --version
`
	return RunCommand(ctx, client, script)
}

// verifyBuilderXcode confirms a full Xcode is installed (not just
// Command Line Tools) and the license has been accepted. The
// xcresult-processor image build runs the Swift xcresult NIF's
// `swift build -c release` directly on the host, which fails
// against CLT because of macOS SDK availability. The expected
// provisioning shape is the Scaleway "macOS + Xcode" preinstalled
// image; this step short-circuits with a clear error when the
// operator ordered the vanilla macOS image by accident.
func verifyBuilderXcode(ctx context.Context, client *ssh.Client) error {
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
	return RunCommand(ctx, client, script)
}

// writeBuildCacheEnv exports TUIST_MIX_BUILD_ROOT in /etc/zshenv.
// /etc/zshenv is the only zsh init file sourced by every zsh
// invocation, including non-login non-interactive shells. The
// runner's per-step shells fall into that category, so ~/.zprofile
// (login only) and ~/.zshrc (interactive only) would both miss them.
//
// Idempotent via a grep-then-append guard so re-runs don't duplicate
// the line. The cache directory is created with the SSH user's
// ownership so the runner's mix invocations can write to it without
// sudo.
func writeBuildCacheEnv(ctx context.Context, client *ssh.Client, sshUser, root string) error {
	if root == "" {
		root = "/opt/tuist-build-cache"
	}
	script := fmt.Sprintf(`set -euo pipefail
sudo mkdir -p %[1]s
sudo chown %[2]s:staff %[1]s
LINE='export TUIST_MIX_BUILD_ROOT=%[1]s'
if ! sudo grep -qxF "$LINE" /etc/zshenv 2>/dev/null; then
  echo "$LINE" | sudo tee -a /etc/zshenv > /dev/null
fi
`, shellQuote(root), shellQuote(sshUser))
	return RunCommand(ctx, client, script)
}

// installActionsRunner downloads the actions/runner tarball into
// /opt/actions-runner, configures it for cfg.GHOrg with the
// operator-supplied short-lived registration token, and installs it
// as a launchd LaunchAgent under the SSH user.
//
// `./svc.sh install <user>` on macOS writes
// ~<user>/Library/LaunchAgents/actions.runner.<repo>.<name>.plist
// and loads it into that user's GUI session. The auto-login
// configured by EnableAutoLogin is what makes that GUI session
// exist at boot, which is what loads the agent after a reboot.
// Without auto-login the runner would only come up when someone
// manually logged in to the host.
//
// --replace lets re-runs swap the existing registration of the same
// name, which is the path the reconciler takes when re-bootstrapping
// the same host after a config change.
//
// The .runner / .credentials / .credentials_rsaparams files are
// cleared before ./config.sh so a host that's been re-registered
// at a different URL doesn't trip "A runner exists with the same
// name" on subsequent config.sh calls. The server-side cleanup of
// the previous runner is the operator's job
// (gh api -X DELETE /orgs/<org>/actions/runners/<id>); we don't do
// it implicitly because the previous runner may legitimately exist
// with the same name (e.g. mid-rotation).
func installActionsRunner(ctx context.Context, client *ssh.Client, sshUser, runnerName string, cfg GHActionsRunnerConfig) error {
	if cfg.GHRunnerRegistrationToken == "" {
		return fmt.Errorf("GHRunnerRegistrationToken is empty; the caller must resolve the registration-token Secret before calling InstallActionsRunner")
	}
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
./svc.sh stop 2>/dev/null || true
./svc.sh uninstall 2>/dev/null || true
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
		shellQuote(cfg.GHRunnerVersion),
		shellQuote(sshUser),
		shellQuote(cfg.GHOrg),
		shellQuote(cfg.GHRunnerRegistrationToken),
		shellQuote(runnerName),
		shellQuote(cfg.GHRunnerLabels),
	)
	return RunCommand(ctx, client, script)
}

// runActionsRunnerInstall is the public entrypoint Run() calls when
// `cfg.GHActionsRunner` is set. Composes the builder-specific steps
// in order: Homebrew + dev tooling, Xcode verify, build-cache env,
// the runner agent itself.
//
// Kept as a single function (rather than four exported helpers) so
// the order is documented in code rather than in the reconciler.
// The reconciler should never call individual builder steps on
// their own; they're not idempotent in isolation (e.g.
// installActionsRunner expects PATH to include /opt/homebrew/bin
// which installBuilderTooling sets up).
func runActionsRunnerInstall(ctx context.Context, client *ssh.Client, sshUser, runnerName string, cfg GHActionsRunnerConfig) error {
	if err := installBuilderTooling(ctx, client); err != nil {
		return fmt.Errorf("install builder tooling: %w", err)
	}
	if err := verifyBuilderXcode(ctx, client); err != nil {
		return fmt.Errorf("verify builder xcode: %w", err)
	}
	if err := writeBuildCacheEnv(ctx, client, sshUser, cfg.TuistMixBuildRoot); err != nil {
		return fmt.Errorf("write build cache env: %w", err)
	}
	if err := installActionsRunner(ctx, client, sshUser, runnerName, cfg); err != nil {
		return fmt.Errorf("install actions runner: %w", err)
	}
	return nil
}
