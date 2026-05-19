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
# Layer split: this is Layer 2 on top of
# `ghcr.io/tuist/macos-tahoe-xcode:<xcode-version-dashes>` (built by
# `infra/macos-xcode-image`). Xcode + dev tools + WWDR certs all
# live in the Layer 1 base; this layer just adds the GitHub Actions
# runner agent, the dispatch loop, and the runner user / launchd
# wiring. Splitting the slow Xcode install out means a Layer 2
# rebuild on every runner-image commit costs ~2 min instead of
# ~30 min.
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
#   /opt/tuist/inject-env.sh                    <- reads kubelet env mount → /etc/tuist.env
#   /Applications/Xcode_<version>.app           <- inherited from Layer 1
#
# The Layer 1 base inherits macos-tahoe-base's `admin` user with a
# `/Users/runner` symlink to `/Users/admin` plus a configured
# `~/.zprofile` (brew shellenv, mise, rbenv init). Our flow creates
# a real `runner` user that *also* points at `/Users/runner` —
# sysadminctl can't overwrite the existing path, so it assigns a
# fresh UID against the symlinked home. Both users end up sharing
# `.zprofile`, which is how the runner's login shell sees the
# brew-installed tools from Layer 1.
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
  description = "Base Tart image (Layer 1: ghcr.io/tuist/macos-tahoe-xcode:<xcode-version-dashes>, e.g. `:26-4-1` or `:26-5`). Bump this to roll the fleet onto a new Xcode."
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
  # opens `fix(runner-image): …` PRs which release-runner-image
  # picks up to rebuild + bump the digest pin. Renovate PRs
  # auto-merge on green CI, same flow we use for other external
  # deps; falling more than ~1 release behind would re-introduce
  # the v2.328-style deprecation risk so the cadence is
  # load-bearing.
  # renovate: datasource=github-releases depName=actions/runner
  default = "2.334.0"
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
  ssh_timeout  = "120s"
  headless     = true
}

build {
  sources = ["source.tart-cli.runner"]

  # Create the `runner` user. macos-tahoe-base (inherited via
  # Layer 1) ships with `admin` as its working user but pre-stages
  # `/Users/runner` as a placeholder carrying ACLs / flags that
  # survive `chown -R`. If we leave it in place, `sysadminctl
  # -addUser runner` logs `Directory at path:/Users/runner already
  # exists` and skips home creation, so the new user never owns
  # its own home and runtime mkdirs like `~/.local/share/mise`
  # blow up with EACCES the first time any step tries to create a
  # top-level subdir we didn't pre-chown.
  #
  # Wipe the placeholder before sysadminctl so it creates a fresh
  # home from scratch with the correct POSIX ownership and the
  # default macOS-user ACLs — no base-image residue to fight.
  #
  # `-admin` adds the user to the admin GROUP, which is what
  # `/etc/sudoers.d/%admin` and `inject-env.sh`'s `root:admin`
  # file ownership reference. Password "runner" is encoded into
  # /etc/kcpassword below so the auto-login flow can unlock the
  # account at boot.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "echo 'admin' | sudo -S rm -rf /Users/runner",
      "echo 'admin' | sudo -S sysadminctl -addUser runner -fullName 'GitHub Actions Runner' -password runner -admin",
      "echo 'admin' | sudo -S mkdir -p /opt/tuist /etc/tuist",
      "echo 'admin' | sudo -S chown root:wheel /opt/tuist"
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
  # Defensively wipe `/Users/runner/actions-runner` before
  # repopulating: macos-tahoe-base's install-actions-runner.sh
  # script may have installed an unpinned runner version under
  # the placeholder /Users/runner that survives the rm -rf above
  # if anything has changed the inheritance order. Removing the
  # dir before recreating it lands an empty, runner-owned tree
  # that the tar extract can populate without fighting any
  # leftover.
  #
  # Create the subdirectories as root + chown to runner instead of
  # `sudo -u runner mkdir` — see the runner-user creation block
  # for why mkdir directly under a freshly-created /Users/runner
  # can fail even after a recursive chown.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "sudo rm -rf /Users/runner/actions-runner",
      "sudo mkdir -p /Users/runner/actions-runner /Users/runner/work",
      "sudo chown runner:staff /Users/runner/actions-runner /Users/runner/work",
      "cd /Users/runner/actions-runner",
      "sudo -u runner rm -rf ./*",
      "sudo -u runner curl -sSL -o actions-runner.tar.gz https://github.com/actions/runner/releases/download/v${var.runner_version}/actions-runner-osx-arm64-${var.runner_version}.tar.gz",
      "sudo -u runner tar xzf actions-runner.tar.gz",
      "sudo -u runner rm actions-runner.tar.gz",
      # Sanity check: configure script exists. We don't run
      # ./config.sh — JIT config is provided at runtime.
      "test -x ./run.sh"
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

  provisioner "shell" {
    inline = [
      "echo 'admin' | sudo -S install -m 0755 /tmp/inject-env.sh /opt/tuist/inject-env.sh",
      "echo 'admin' | sudo -S install -m 0755 /tmp/dispatch-poll.sh /opt/tuist/dispatch-poll.sh",
      "rm -f /tmp/inject-env.sh /tmp/dispatch-poll.sh"
    ]
  }

  # Passwordless sudo for runner. The agent runs as the `runner`
  # user in a real desktop session (LaunchAgent + auto-login),
  # not as root, so the few privileged operations the agent needs
  # — installing /etc/tuist.env from the kubelet env mount,
  # halting the VM at job exit — go through sudo. Passwordless
  # because the VM is ephemeral and single-tenant; the entire OS
  # is the customer's job environment.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "echo 'admin' | sudo -S sh -c 'echo \"runner ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/runner-nopasswd'",
      "echo 'admin' | sudo -S chmod 0440 /etc/sudoers.d/runner-nopasswd",
      "echo 'admin' | sudo -S chown root:wheel /etc/sudoers.d/runner-nopasswd",
      "sudo -u runner sudo -n true"
    ]
  }

  # Auto-login as runner so a desktop session exists at boot and
  # loginwindow loads /Users/runner/Library/LaunchAgents agents.
  # macOS implements auto-login via /etc/kcpassword (XOR-encoded
  # password using Apple's well-known key) + the autoLoginUser
  # preference. The encoded payload for password "runner" is the
  # 6 password bytes followed by 6 zero-pad bytes, each XOR'd
  # against the 12-byte Apple key — total 12 bytes (one full
  # key-length block).
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "printf '\\x0f\\xfc\\x3c\\x4d\\xb7\\xce\\xdd\\xea\\xa3\\xb9\\x1f\\xb5' > /tmp/kcpassword",
      "sudo install -m 0600 -o root -g wheel /tmp/kcpassword /etc/kcpassword",
      "rm -f /tmp/kcpassword",
      "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser runner"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/launchd.plist"
    destination = "/tmp/dev.tuist.runner.plist"
  }

  # Install as a LaunchAgent under runner's home so it loads
  # inside runner's user session (auto-login above guarantees the
  # session exists at boot). User-owned (runner:staff, 0644) per
  # Apple's LaunchAgent ownership rules.
  #
  # Same root-create + chown pattern as the actions-runner block:
  # `/Users/runner/Library` is part of the placeholder home and
  # rejects writes from the runner UID even after `chown -R`.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "sudo mkdir -p /Users/runner/Library/LaunchAgents",
      "sudo chown runner:staff /Users/runner/Library /Users/runner/Library/LaunchAgents",
      "sudo install -m 0644 -o runner -g staff /tmp/dev.tuist.runner.plist /Users/runner/Library/LaunchAgents/dev.tuist.runner.plist",
      "rm -f /tmp/dev.tuist.runner.plist",
      "sudo mkdir -p /var/log/tuist-runner",
      "sudo chown runner:staff /var/log/tuist-runner"
    ]
  }

  # Sanity check: tools customers expect on a GitHub-parity macOS
  # runner have to be reachable from the agent's runtime
  # environment. The agent wraps its entrypoint in `zsh -lc`, so
  # ~/.zprofile is sourced (Homebrew shellenv, mise, rbenv init,
  # PATH additions for the Layer 1 base's pre-installed tools).
  # A future base-image bump that moves Homebrew's prefix or drops
  # a formula would silently make tools unreachable from step
  # shells; resolve each tool against the same login-shell
  # environment so image-build CI fails loudly instead of customer
  # workflows. xcrun + xcresulttool double as the proof that Layer
  # 1's Xcode install + `xcode-select -s` propagated.
  #
  # Tuist itself isn't in the list — customer workflows install it
  # via mise / brew so they own the version pin.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "sudo -u runner /bin/zsh -lc 'for tool in brew mise gh git-lfs jq yq swiftlint swiftformat xcbeautify fastlane pod carthage xcodes xcrun xcresulttool; do command -v \"$tool\" >/dev/null 2>&1 || { echo \"sanity check: $tool not reachable in runner login shell — base image regression\" >&2; exit 1; }; done'",
      "sudo -u runner /bin/zsh -lc '/usr/bin/xcrun xcresulttool version'"
    ]
  }
}
