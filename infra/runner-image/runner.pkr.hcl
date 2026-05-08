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
#  3. Polls the dispatch URL on a 5 s loop. While the Pod is idle
#     the server returns 204 — the script sleeps and retries.
#  4. Once the server returns 200 with `encoded_jit_config`, the
#     script writes the JIT to a temp file and execs
#     `./run.sh --jitconfig $JIT` against the GitHub Actions
#     runner under /opt/actions-runner.
#  5. The runner accepts a single queued job (JIT config implies
#     ephemeral=true), runs the workflow, and exits.
#  6. tart-kubelet observes the VM stop, transitions the Pod to
#     Completed, and the next reconcile tick creates a fresh Pod.
#
# Image layout:
#   /opt/actions-runner/        <- GitHub Actions runner binary
#   /opt/tuist/dispatch-poll.sh <- the dispatch poll loop
#   /opt/tuist/inject-env.sh    <- reads kubelet env mount → /etc/tuist.env
#   /Library/LaunchDaemons/dev.tuist.runner.plist
#
# Note that the runner is registered with GitHub at *job* time,
# not image-build time — the image carries the runner binary but
# no credentials. The JIT config delivered via dispatch is the
# only piece that authenticates this VM as a runner for any
# specific repo.

variable "base_image" {
  type        = string
  description = "Base Tart image. Cirrus Labs ships macOS images with Xcode preinstalled, which is what most iOS/macOS workflows expect."
  default     = "ghcr.io/cirruslabs/macos-tahoe-xcode:26.4"
}

variable "output_image" {
  type        = string
  description = "Output image name."
  default     = "tuist-runner"
}

variable "runner_version" {
  type        = string
  description = "GitHub Actions runner version. https://github.com/actions/runner/releases."
  # Bumped after 2.328.0 was deprecated by GitHub mid-rollout —
  # the runner registers cleanly but the broker channel returns
  # `Runner version v2.328.0 is deprecated and cannot receive
  # messages` on the first long-poll, so the runner exits and
  # GH never dispatches jobs. Pin the latest stable; the actions
  # runner has a runtime auto-update flag (--disableupdate=false)
  # that we keep enabled, but baking in a current version
  # avoids the registration-then-immediate-deprecation cycle on
  # cold-cache fleet bring-up.
  default     = "2.334.0"
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

  provisioner "shell" {
    inline = [
      "echo 'admin' | sudo -S mkdir -p /opt/actions-runner /opt/tuist /etc/tuist",
      "echo 'admin' | sudo -S chown admin:staff /opt/actions-runner /opt/tuist"
    ]
  }

  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "cd /opt/actions-runner",
      "curl -sSL -o actions-runner.tar.gz https://github.com/actions/runner/releases/download/v${var.runner_version}/actions-runner-osx-arm64-${var.runner_version}.tar.gz",
      "tar xzf actions-runner.tar.gz",
      "rm actions-runner.tar.gz",
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

  provisioner "file" {
    source      = "${path.root}/launchd.plist"
    destination = "/tmp/dev.tuist.runner.plist"
  }

  provisioner "shell" {
    inline = [
      "echo 'admin' | sudo -S install -m 0644 /tmp/dev.tuist.runner.plist /Library/LaunchDaemons/dev.tuist.runner.plist",
      "rm -f /tmp/dev.tuist.runner.plist",
      "echo 'admin' | sudo -S chown root:wheel /Library/LaunchDaemons/dev.tuist.runner.plist",
      "echo 'admin' | sudo -S mkdir -p /var/log/tuist-runner",
      "echo 'admin' | sudo -S chown admin:staff /var/log/tuist-runner"
    ]
  }
}
