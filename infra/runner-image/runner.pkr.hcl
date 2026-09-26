packer {
  required_plugins {
    tart = {
      version = ">= 1.16.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

# Build the Tart VM image hosted on the customer-runner Mac mini
# fleet. Each Pod the tart-kubelet runtime schedules onto a runner
# Mac mini boots a copy of this image as a Tart VM. The VM:
#
#  1. Runs `dispatch-poll.sh` from a launchd job at boot.
#  2. The script reads TUIST_RUNNER_DISPATCH_URL +
#     TUIST_RUNNER_POD_UID + TUIST_RUNNER_DISPATCH_TOKEN from
#     /etc/tuist.env (staged by tart-kubelet via the env-mount
#     flow at /Volumes/My Shared Files/env/tuist.env, then
#     re-emitted as /etc/tuist.env by inject-env.sh on first boot).
#  3. Polls the dispatch URL on a 2 s loop. While the Pod is idle
#     the server returns 204 — the script sleeps and retries.
#  4. Once the server returns 200 with `encoded_jit_config`, the
#     script writes the JIT to a temp file and execs
#     `./run.sh --jitconfig $JIT` against the GitHub Actions
#     runner under /Users/runner/actions-runner.
#  5. The runner accepts a single queued job (JIT config implies
#     ephemeral=true), runs the workflow, and exits.
#  6. tart-kubelet observes the VM stop, transitions the Pod to
#     Completed, and the next reconcile tick creates a fresh Pod.
#
# Builds on top of `ghcr.io/tuist/macos-tahoe-xcode:<xcode-version-dashes>`
# (built by `infra/macos-xcode-image`). Xcode + dev tools + WWDR
# certs all live in the macos-tahoe-xcode base; this build just adds
# the GitHub Actions runner agent, the dispatch loop, and the runner
# user / launchd wiring. Splitting the slow Xcode install out means
# a rebuild on every runner-image commit costs ~2 min instead of
# ~30 min.
#
# Active Xcode versions baked per release are listed in
# `infra/runner-image/profiles.json`. `runner-image-release.yml`
# publishes one
# `ghcr.io/tuist/tuist-runner:macos-<xcode-dashes>-<semver>` tag each
# that the managed envs' charts reference via
# `runnersFleet.runnerImageSemver`. Keep the list aligned with
# `runnersFleet.xcodeVersions` in
# `infra/helm/tuist/values-managed-common.yaml` — every Xcode that
# ships a pool needs an image published for it.
#
# Image layout (mirrors GitHub-hosted macOS paths so on-disk
# artifacts that bake absolute paths — SwiftPM `.build/checkouts/`,
# Xcode DerivedData, `actions/cache` payloads — work interchangeably
# between hosted and self-hosted runs without per-environment cache
# keys):
#   /Users/runner/                              <- runtime user
#   /Users/runner/actions-runner/               <- GitHub Actions runner binary
#   /Users/runner/work/<owner>/<repo>           <- workspace, set via JIT work_folder
#   /Users/runner/Library/LaunchAgents/         <- dev.tuist.runner.plist
#   /opt/tuist/dispatch-poll.sh                 <- the dispatch poll loop (root-owned)
#   /opt/tuist/metrics-poll.sh                  <- machine-metrics sampler (forked during a job)
#   /opt/tuist/inject-env.sh                    <- reads kubelet env mount → /etc/tuist.env
#   /opt/tuist/runner-shell-agent               <- trusted interactive shell bridge
#   /opt/tuist/tuist-cas-proxy                  <- compilation-cache (CAS) prune client,
#                                                  the last-resort one for jobs that never
#                                                  run Tuist and so install no proxy of
#                                                  their own; see cas_proxy_client
#   /Applications/Xcode_<version>.app           <- inherited from the base
#
# Jobs run as the account that built the image, as on GitHub-hosted
# images. The macos-tahoe-xcode base provisions everything as
# macos-tahoe-base's auto-login `admin` user (uid 501), with
# `/Users/runner` as a symlink to `/Users/admin`. This build runs as
# `admin` too, writing runner paths through that symlink, and a
# provisioner near the end renames the account to `runner` and moves its
# home to `/Users/runner`. Everything the base and this build set up
# (the Homebrew prefix, `~/.zprofile`, rbenv's Rubies, the Metal
# Toolchain) belongs to the job account without being handed over.
#
# Provisioners after the rename run as `sudo -u runner -H`. The `-H`
# is load-bearing: macOS sudoers carries `env_keep += "HOME"`.
#
# Note that the runner is registered with GitHub at *job* time,
# not image-build time — the image carries the runner binary but
# no credentials. The JIT config delivered via dispatch is the
# only piece that authenticates this VM as a runner for any
# specific repo. The matching `Tuist.Runners.mint_jit` call passes
# `work_folder: "/Users/runner/work"` so the agent's workspace
# lands at the same absolute path GitHub-hosted runners use.

variable "base_image" {
  type        = string
  description = "Base Tart image (ghcr.io/tuist/macos-tahoe-xcode:<xcode-version-dashes>, e.g. `:26-4-1` or `:26-5`). Bump this to roll the fleet onto a new Xcode."
  default     = "ghcr.io/tuist/macos-tahoe-xcode:26-4-1"
}

variable "output_image" {
  type        = string
  description = "Output image name."
  default     = "tuist-runner"
}

variable "runner_version" {
  type        = string
  description = "GitHub Actions runner version. https://github.com/actions/runner/releases."
  # Pinned: the runner is launched with `--disableupdate` so what
  # ships is what runs — no opaque mid-VM self-upgrades, no race
  # against GitHub's broker-deprecation message on cold boot.
  # Renovate watches actions/runner releases (see renovate.json's
  # custom regex manager keyed off the marker comment below) and
  # opens `fix(runner-image): …` PRs which runner-image-release.yml
  # picks up to rebuild + bump the chart's image pin. Renovate PRs
  # auto-merge on green CI, same flow we use for other external
  # deps; falling more than ~1 release behind would re-introduce
  # the v2.328-style deprecation risk so the cadence is
  # load-bearing.
  #
  # That cadence is only as good as Renovate's PR budget: a backlog
  # of unreviewed PRs once filled the concurrency limit and this pin
  # silently sat three releases behind until GitHub retired it. See
  # renovate.json for the limits and the dependency dashboard that
  # now make a withheld bump visible.
  # renovate: datasource=github-releases depName=actions/runner
  default = "2.337.0"
}

variable "buildkite_agent_sha256_darwin_arm64" {
  type        = string
  description = "SHA256 of the darwin-arm64 agent tarball, from the release's own SHA256SUMS."
  # Carried with `buildkite_agent_version`: the download is verified
  # against this before extraction, so a stale value fails the build
  # rather than installing an unchecked binary.
  default = "67bd0dbe9417776a9f7bee02bcbf840e169f37e28ae36dd0a5184c61312438b2"
}

variable "buildkite_agent_version" {
  type        = string
  description = "Buildkite agent version. https://github.com/buildkite/agent/releases."
  # Same pinning rationale as `runner_version`, and the same Renovate
  # flow keeps it current.
  # renovate: datasource=github-releases depName=buildkite/agent
  default = "3.138.0"
}

# VM CPU/memory baked into the Tart image. Kept at 4 / 8 (same
# shape as the xcresult-processor image) so the build runs on
# the existing M1-M `vm-image-builder` Mac mini — the host has
# 16 GB total, so a 16 GB VM exceeds Tart's
# `maximumAllowedMemorySize` and Packer aborts at boot.
#
# Trade-off: at deploy time customer VMs use these baked sizes
# (4 vCPU / 8 GB) rather than the M4-S host's full 8 vCPU / 16
# GB. The Pod-level resource request (`4000m / 14Gi` in
# `Tuist.Runners.PodSpec`) still pins exactly one runner Pod
# per Mac mini, so the build-time consistency property is
# preserved — neighbour VMs can't contend for resources because
# there are no neighbours. To use the host's full resources at
# runtime, tart-kubelet would need to invoke `tart set` before
# `tart run`. That's a v2 hardening item; until it lands, 8 GB
# is the customer-facing VM size.
variable "cpu_count" {
  type    = number
  default = 4
}

variable "memory_gb" {
  type    = number
  default = 8
}

source "tart-cli" "runner" {
  vm_base_name = var.base_image
  vm_name      = var.output_image
  cpu_count    = var.cpu_count
  memory_gb    = var.memory_gb
  ssh_username = "admin"
  ssh_password = "admin"
  # First boot of a freshly-cloned Tart base image runs macOS first-time
  # setup (kextcache rebuild, Spotlight indexing, APFS expansion,
  # AssetCacheLocator, first-run launchd jobs) which can take 10+ min
  # to reach an SSH-ready state. Cached re-clones (the state of long-
  # lived builder hosts) skip that work and answer in ~30s, which is why
  # tight values held for years on the original Mac mini but timed out
  # on newly-onboarded hosts. 15m gives headroom for the cold path on a
  # cirruslabs Tahoe base; the warm path returns long before then.
  ssh_timeout = "15m"
  headless    = true
}

build {
  sources = ["source.tart-cli.runner"]

  # The rename at the end of this build depends on these, so fail
  # before doing any work if the base stops providing them.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "[ \"$(id -un)\" = admin ] && [ \"$(id -u)\" = 501 ] || { echo 'base image: expected to provision as admin (uid 501)' >&2; exit 1; }",
      "[ \"$(readlink /Users/runner)\" = /Users/admin ] || { echo 'base image: /Users/runner is no longer a symlink to /Users/admin' >&2; exit 1; }",
      "echo 'admin' | sudo -S mkdir -p /opt/tuist /etc/tuist",
      "echo 'admin' | sudo -S chown root:wheel /opt/tuist"
    ]
  }

  # The runner auto-login opens a real desktop session so launchd can
  # run the GitHub Actions agent. On fresh macOS images that first
  # desktop can be intercepted by Setup Assistant's "Update Mac
  # Automatically" pane, which is exactly what the dashboard VNC
  # would then show. macOS 11+ rejects silent .mobileconfig installs,
  # so seed the macOS 15+ SkipSetupItems preferences directly and also
  # write the older seen flags that previous Setup Assistant releases
  # still consult.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "echo 'admin' | sudo -S true",
      "SETUP_ITEMS=(AppleID Appearance Biometric Diagnostics FileVault iCloudStorage Intelligence Location Privacy ScreenTime Siri SoftwareUpdate UnlockWithWatch UpdateCompleted Welcome)",
      "sudo mkdir -p '/Library/Managed Preferences' '/Library/Managed Preferences/runner'",
      "write_skip_items() { local plist=\"$1\"; sudo rm -f \"$plist\"; sudo plutil -create xml1 \"$plist\"; sudo /usr/libexec/PlistBuddy -c 'Add :SkipSetupItems array' \"$plist\"; for item in \"$${SETUP_ITEMS[@]}\"; do sudo /usr/libexec/PlistBuddy -c \"Add :SkipSetupItems: string $item\" \"$plist\"; done; sudo chmod 644 \"$plist\"; }",
      "write_skip_items '/Library/Managed Preferences/com.apple.SetupAssistant.managed.plist'",
      "write_skip_items '/Library/Managed Preferences/runner/com.apple.SetupAssistant.managed.plist'",
      "write_skip_items '/Library/Preferences/com.apple.SetupAssistant.managed.plist'",
      "write_skip_items \"$HOME/Library/Preferences/com.apple.SetupAssistant.managed.plist\"",
      "sudo chown \"$(id -u):staff\" \"$HOME/Library/Preferences/com.apple.SetupAssistant.managed.plist\"",
      "sudo chmod 755 '/Library/Managed Preferences' '/Library/Managed Preferences/runner'",
      "PRODUCT_VERSION=$(sw_vers -productVersion)",
      "BUILD_VERSION=$(sw_vers -buildVersion)",
      "sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeCloudSetup -bool true",
      "sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeSiriSetup -bool true",
      "sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeePrivacy -bool true",
      "sudo defaults write /Library/Preferences/com.apple.SetupAssistant LastSeenCloudProductVersion \"$PRODUCT_VERSION\"",
      "sudo defaults write /Library/Preferences/com.apple.SetupAssistant LastSeenBuddyBuildVersion \"$BUILD_VERSION\"",
      "defaults write com.apple.SetupAssistant DidSeeCloudSetup -bool true",
      "defaults write com.apple.SetupAssistant DidSeeSiriSetup -bool true",
      "defaults write com.apple.SetupAssistant DidSeePrivacy -bool true",
      "defaults write com.apple.SetupAssistant LastSeenCloudProductVersion \"$PRODUCT_VERSION\"",
      "defaults write com.apple.SetupAssistant LastSeenBuddyBuildVersion \"$BUILD_VERSION\"",
      "defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false",
      "defaults write com.apple.SoftwareUpdate AutomaticDownload -bool false"
    ]
  }

  # Base images built before the Metal Toolchain was added to them
  # have none. Xcode 26.1 only exposes a downloaded toolchain to the
  # user that installed it, which this account is.
  #
  # The toolchain build is passed explicitly: without it `xcodebuild`
  # asks Apple for a toolchain under the Xcode's own build, and Apple
  # publishes some under a different one (Xcode 26.4.1 is 17E202, its
  # toolchain 17E188). Apple's downloadable index maps one to the
  # other; the last match is the one Xcode itself picks when there
  # are several.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "if /usr/bin/xcrun metal --version >/dev/null 2>&1; then exit 0; fi",
      "XCODE_BUILD=$(xcodebuild -version | awk '/^Build version/ {print $3}')",
      "INDEX=$(mktemp)",
      "curl -fsSL https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex -o \"$INDEX\"",
      "METAL_BUILD=''",
      "for i in $(seq 0 $(($(plutil -extract xcodeToOtherDownloadablesMappings raw -o - \"$INDEX\") - 1))); do if [ \"$(plutil -extract xcodeToOtherDownloadablesMappings.$i.assetType raw -o - \"$INDEX\")\" = metalToolchain ] && [ \"$(plutil -extract xcodeToOtherDownloadablesMappings.$i.xcodeBuildUpdate raw -o - \"$INDEX\")\" = \"$XCODE_BUILD\" ]; then METAL_BUILD=$(plutil -extract xcodeToOtherDownloadablesMappings.$i.assetBuildUpdate raw -o - \"$INDEX\"); fi; done",
      "rm -f \"$INDEX\"",
      "[ -n \"$METAL_BUILD\" ] || { echo \"Apple's downloadable index maps no Metal Toolchain to Xcode build $XCODE_BUILD\" >&2; exit 1; }",
      "xcodebuild -downloadComponent MetalToolchain -buildVersion \"$METAL_BUILD\""
    ]
  }

  # Install the Actions runner agent under runner's home so the
  # binary, its `_diag` logs, and any side data it writes land
  # under `/Users/runner/...` — matching GitHub-hosted's layout
  # (their agent installs at `/Users/runner/runners/<version>/`).
  # `--work` for the workspace is set at JIT-generation time
  # (`work_folder: "/Users/runner/work"`), so the actual checkout
  # ends up at the GH-parity path regardless of the agent's home.
  #
  # Wipe `/Users/runner/actions-runner` before repopulating, in case
  # the base installed an unpinned runner version there.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "rm -rf /Users/runner/actions-runner",
      "mkdir -p /Users/runner/actions-runner /Users/runner/work",
      "cd /Users/runner/actions-runner",
      "curl -sSL -o actions-runner.tar.gz https://github.com/actions/runner/releases/download/v${var.runner_version}/actions-runner-osx-arm64-${var.runner_version}.tar.gz",
      "tar xzf actions-runner.tar.gz",
      "rm actions-runner.tar.gz",
      # Sanity check: configure script exists. We don't run
      # ./config.sh — JIT config is provided at runtime.
      "test -x ./run.sh"
    ]
  }

  # The Buildkite agent lives alongside the GitHub one rather than in a
  # second image. Which of the two runs is a per-job decision the server
  # makes at dispatch, so a Pod has to be able to serve either; forking
  # the image would double the fleet's warm-pool partitioning to save
  # about 30 MB.
  #
  # Pinned for the same reason `runner_version` is: the version that ran a
  # job should be the version we baked. The agent has no self-update, so
  # pinning here is the whole mechanism.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "cd /tmp",
      "curl -sSL -o buildkite-agent.tar.gz https://github.com/buildkite/agent/releases/download/v${var.buildkite_agent_version}/buildkite-agent-darwin-arm64-${var.buildkite_agent_version}.tar.gz",
      "echo '${var.buildkite_agent_sha256_darwin_arm64}  buildkite-agent.tar.gz' | shasum -a 256 -c -",
      "mkdir -p /tmp/buildkite-agent-dist",
      "tar xzf buildkite-agent.tar.gz -C /tmp/buildkite-agent-dist",
      "echo 'admin' | sudo -S install -m 0755 -o root -g wheel /tmp/buildkite-agent-dist/buildkite-agent /opt/tuist/buildkite-agent",
      "rm -rf buildkite-agent.tar.gz /tmp/buildkite-agent-dist",
      "/opt/tuist/buildkite-agent --version"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/inject-env.sh"
    destination = "/tmp/inject-env.sh"
  }

  provisioner "file" {
    source      = "${path.root}/dispatch-poll.sh"
    destination = "/tmp/dispatch-poll.sh"
  }

  provisioner "file" {
    source      = "${path.root}/metrics-poll.sh"
    destination = "/tmp/metrics-poll.sh"
  }

  provisioner "file" {
    source      = "${path.root}/buildkite-hooks"
    destination = "/tmp/buildkite-hooks"
  }

  provisioner "file" {
    source      = "${path.root}/build/tuist-gitlab-runner"
    destination = "/tmp/tuist-gitlab-runner"
  }

  provisioner "file" {
    source      = "${path.root}/build/runner-shell-agent"
    destination = "/tmp/runner-shell-agent"
  }

  provisioner "file" {
    source      = "${path.root}/runner-shell-agent-supervisor.sh"
    destination = "/tmp/runner-shell-agent-supervisor.sh"
  }

  # Built by the workflow from cas-plugin/ (see "Build CAS prune client"), the
  # same way runner-shell-agent is. It is only ever invoked as
  # `--prune`/`--drain`; it never serves, so the image carries no daemon.
  provisioner "file" {
    source      = "${path.root}/build/tuist-cas-proxy"
    destination = "/tmp/tuist-cas-proxy"
  }

  provisioner "file" {
    source      = "${path.root}/runner-shell-agent.plist"
    destination = "/tmp/dev.tuist.runner-shell-agent.plist"
  }

  provisioner "shell" {
    inline = [
      "echo 'admin' | sudo -S install -m 0755 /tmp/inject-env.sh /opt/tuist/inject-env.sh",
      "echo 'admin' | sudo -S install -m 0755 /tmp/dispatch-poll.sh /opt/tuist/dispatch-poll.sh",
      "echo 'admin' | sudo -S install -m 0755 /tmp/metrics-poll.sh /opt/tuist/metrics-poll.sh",
      "echo 'admin' | sudo -S install -m 0755 /tmp/runner-shell-agent /opt/tuist/runner-shell-agent",
      "echo 'admin' | sudo -S install -m 0755 /tmp/tuist-gitlab-runner /opt/tuist/tuist-gitlab-runner",
      "echo 'admin' | sudo -S install -m 0755 /tmp/runner-shell-agent-supervisor.sh /opt/tuist/runner-shell-agent-supervisor.sh",
      "echo 'admin' | sudo -S install -m 0755 /tmp/tuist-cas-proxy /opt/tuist/tuist-cas-proxy",
      "echo 'admin' | sudo -S install -m 0644 -o root -g wheel /tmp/dev.tuist.runner-shell-agent.plist /Library/LaunchDaemons/dev.tuist.runner-shell-agent.plist",
      # Global agent hooks: `buildkite-agent --hooks-path` points here, so
      # these run for every job the agent takes regardless of what the
      # customer's own repository defines.
      "echo 'admin' | sudo -S mkdir -p /opt/tuist/buildkite-hooks",
      "echo 'admin' | sudo -S install -m 0755 /tmp/buildkite-hooks/environment /opt/tuist/buildkite-hooks/environment",
      "echo 'admin' | sudo -S install -m 0755 /tmp/buildkite-hooks/post-command /opt/tuist/buildkite-hooks/post-command",
      "echo 'admin' | sudo -S install -m 0755 /tmp/buildkite-hooks/pre-exit /opt/tuist/buildkite-hooks/pre-exit",
      "rm -rf /tmp/inject-env.sh /tmp/dispatch-poll.sh /tmp/metrics-poll.sh /tmp/runner-shell-agent /tmp/runner-shell-agent-supervisor.sh /tmp/tuist-cas-proxy /tmp/dev.tuist.runner-shell-agent.plist /tmp/buildkite-hooks"
    ]
  }

  # Passwordless sudo for runner. The GitHub Actions runner runs as
  # the `runner` user in a real desktop session (LaunchAgent +
  # auto-login), so the few privileged operations the dispatch loop
  # needs — installing /etc/tuist.env from the kubelet env mount,
  # halting the VM at job exit — go through sudo. Passwordless because
  # the VM is ephemeral and single-tenant; the entire OS is the
  # customer's job environment.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "echo 'admin' | sudo -S sh -c 'echo \"runner ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/runner-nopasswd'",
      "echo 'admin' | sudo -S chmod 0440 /etc/sudoers.d/runner-nopasswd",
      "echo 'admin' | sudo -S chown root:wheel /etc/sudoers.d/runner-nopasswd",
      "sudo visudo -c -f /etc/sudoers.d/runner-nopasswd"
    ]
  }

  # Auto-login as runner so a desktop session exists at boot and
  # loginwindow loads /Users/runner/Library/LaunchAgents agents.
  # macOS implements auto-login via /etc/kcpassword (XOR-encoded
  # password using Apple's well-known key) + the autoLoginUser
  # preference. The encoded payload for password "runner" is the
  # 6 password bytes followed by 6 zero-pad bytes, each XOR'd
  # against the 11-byte Apple key.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "printf '\\x0f\\xfc\\x3c\\x4d\\xb7\\xce\\xdd\\xea\\xa3\\xb9\\x1f\\x7d' > /tmp/kcpassword",
      "sudo install -m 0600 -o root -g wheel /tmp/kcpassword /etc/kcpassword",
      "rm -f /tmp/kcpassword",
      "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser -string runner",
      "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUserUID -int \"$(id -u)\"",
      "sudo defaults write /Library/Preferences/com.apple.loginwindow DisableFDEAutoLogin -bool false",
      "sudo pmset -a sleep 0 displaysleep 0 disksleep 0",
      "sudo defaults write /Library/Preferences/com.apple.screensaver idleTime -int 0",
      "sudo defaults write /Library/Preferences/com.apple.screensaver askForPassword -int 0",
      "sudo defaults write /Library/Preferences/com.apple.screensaver askForPasswordDelay -int 0",
      "sudo defaults -currentHost write com.apple.screensaver idleTime -int 0",
      "sudo defaults -currentHost write com.apple.screensaver askForPassword -int 0",
      "sudo defaults -currentHost write com.apple.screensaver askForPasswordDelay -int 0",
      "sudo defaults write /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay -int 0",
      "defaults write com.apple.screensaver idleTime -int 0",
      "defaults write com.apple.screensaver askForPassword -int 0",
      "defaults write com.apple.screensaver askForPasswordDelay -int 0",
      "defaults -currentHost write com.apple.screensaver idleTime -int 0",
      "defaults -currentHost write com.apple.screensaver askForPassword -int 0",
      "defaults -currentHost write com.apple.screensaver askForPasswordDelay -int 0",
      "sudo /usr/bin/python3 - <<'CHECK'\nimport sys\nkey = bytes([0x7d, 0x89, 0x52, 0x23, 0xd2, 0xbc, 0xdd, 0xea, 0xa3, 0xb9, 0x1f])\nwith open('/etc/kcpassword', 'rb') as f:\n    enc = f.read()\ndec = bytes(b ^ key[i % len(key)] for i, b in enumerate(enc))\nif dec.startswith(b'<sealed>'):\n    sys.stderr.write('kcpassword was replaced by macOS with <sealed>; runner auto-login would boot to the password screen\\n')\n    sys.exit(1)\nif dec != b'runner' + bytes(6):\n    sys.stderr.write('kcpassword does not decode to the runner auto-login payload\\n')\n    sys.exit(1)\nCHECK"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/launchd.plist"
    destination = "/tmp/dev.tuist.runner.plist"
  }

  # Install as a LaunchAgent under runner's home so it loads
  # inside runner's user session (auto-login above guarantees the
  # session exists at boot). User-owned (0644) per Apple's
  # LaunchAgent ownership rules.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "mkdir -p /Users/runner/Library/LaunchAgents",
      "install -m 0644 /tmp/dev.tuist.runner.plist /Users/runner/Library/LaunchAgents/dev.tuist.runner.plist",
      "rm -f /tmp/dev.tuist.runner.plist",
      "sudo mkdir -p /var/log/tuist-runner",
      "sudo chown \"$(id -u):staff\" /var/log/tuist-runner"
    ]
  }

  # Rename `admin` to `runner`, keeping uid 501, and move its home to
  # `/Users/runner`. `/Users/admin` becomes a symlink to the new home
  # for absolute paths the base baked in.
  #
  # The password changes first, as the account itself, so the login
  # keychain follows it; auto-login above already carries the new
  # one. Group memberships are recorded by name and move explicitly.
  # `runner-nopasswd` is in place before the name changes, which is
  # what lets this session and Packer's shutdown keep using sudo.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "dscl . -passwd /Users/admin admin runner",
      "KEYCHAIN=\"$HOME/Library/Keychains/login.keychain-db\"",
      "if [ -f \"$KEYCHAIN\" ]; then security set-keychain-password -o admin -p runner \"$KEYCHAIN\" 2>/dev/null || true; security unlock-keychain -p runner \"$KEYCHAIN\"; fi",
      "sudo sysadminctl -screenLock off -password runner || true",
      "for group in $(dscl . -list /Groups GroupMembership | awk '{ for (i = 2; i <= NF; i++) if ($i == \"admin\") print $1 }'); do sudo dscl . -delete \"/Groups/$group\" GroupMembership admin; sudo dscl . -append \"/Groups/$group\" GroupMembership runner; done",
      "sudo rm /Users/runner",
      "sudo mv /Users/admin /Users/runner",
      "sudo ln -s /Users/runner /Users/admin",
      "sudo dscl . -create /Users/admin NFSHomeDirectory /Users/runner",
      "sudo dscl . -create /Users/admin RealName 'GitHub Actions Runner'",
      "sudo dscl . -change /Users/admin RecordName admin runner",
      "sudo rm -f /etc/sudoers.d/admin-nopasswd",
      "sudo dscacheutil -flushcache",
      "[ \"$(id -un 501)\" = runner ] || { echo 'rename: uid 501 is not runner' >&2; exit 1; }",
      "! id admin >/dev/null 2>&1 || { echo 'rename: an admin user still exists' >&2; exit 1; }",
      "[ \"$(dscl . -read /Users/runner NFSHomeDirectory | awk '{ print $2 }')\" = /Users/runner ] || { echo 'rename: runner home is not /Users/runner' >&2; exit 1; }",
      "dseditgroup -o checkmember -m runner admin >/dev/null || { echo 'rename: runner is not in the admin group' >&2; exit 1; }",
      "dscl . -authonly runner runner || { echo 'rename: runner password is not runner' >&2; exit 1; }",
      "sudo -u runner -H sudo -n true"
    ]
  }

  # Sanity check: tools customers expect on a GitHub-parity macOS
  # runner have to be reachable from the agent's runtime
  # environment. The agent wraps its entrypoint in `zsh -lc`, so
  # the base's ~/.zprofile is sourced (Homebrew shellenv, rbenv init,
  # PATH additions for the macos-tahoe-xcode base's pre-installed
  # tools). A future base-image bump that moves Homebrew's prefix
  # or drops a formula would silently make tools unreachable from
  # step shells; resolve each tool against the same login-shell
  # environment so image-build CI fails loudly instead of customer
  # workflows. xcresulttool isn't on PATH; xcrun resolves it, so the
  # explicit `xcrun xcresulttool version` below doubles as proof
  # that the base's Xcode install + `xcode-select -s` propagated.
  # `xcrun metal --version` proves the Metal Toolchain is visible to
  # `runner`, and `rbenv versions` that the base's Rubies are.
  #
  # Tuist itself isn't in the list — customer workflows install it
  # via mise / brew so they own the version pin.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "sudo -u runner -H /bin/zsh -lc 'for tool in brew mise rbenv gh git-lfs jq yq swiftlint swiftformat xcbeautify fastlane pod carthage xcodes xcrun; do command -v \"$tool\" >/dev/null 2>&1 || { echo \"sanity check: $tool not reachable in runner login shell — base image regression\" >&2; exit 1; }; done'",
      "sudo -u runner -H /bin/zsh -lc '/usr/bin/xcrun xcresulttool version'",
      "sudo -u runner -H /bin/zsh -lc '/usr/bin/xcrun metal --version'",
      "sudo -u runner -H /bin/zsh -lc '[ -n \"$(rbenv versions --bare)\" ]' || { echo 'sanity check: no rbenv Ruby versions for runner' >&2; exit 1; }"
    ]
  }

  # Sanity check: `brew` being on PATH says nothing about whether a
  # workflow step can install with it. The check above passed for
  # months while every `brew install` on this image failed on prefix
  # ownership, so assert the operation rather than the binary.
  # `hello` is Homebrew's own smoke-test formula: no dependencies,
  # installs in seconds, and uninstalling leaves the image clean.
  #
  # HOMEBREW_NO_AUTO_UPDATE keeps the check off the network's
  # critical path — it would otherwise re-fetch every tap and make
  # image builds fail on transient GitHub blips. What this exercises
  # is writing into Cellar and the lock/var dirs, and `brew`'s
  # download and bootsnap caches under `$HOME`.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "sudo -u runner -H /bin/zsh -lc 'HOMEBREW_NO_AUTO_UPDATE=1 brew install hello' || { echo 'sanity check: unprivileged brew install failed for the runner user — Homebrew prefix ownership regression' >&2; exit 1; }",
      "sudo -u runner -H /bin/zsh -lc 'HOMEBREW_NO_AUTO_UPDATE=1 brew uninstall hello'"
    ]
  }
}
