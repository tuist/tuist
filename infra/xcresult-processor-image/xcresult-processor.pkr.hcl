packer {
  required_plugins {
    tart = {
      version = ">= 1.16.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

# Build the Tart VM image that hosts the Tuist xcresult processor on macOS.
#
# The image is the per-Pod artifact: every Pod the tart-cri runtime
# schedules onto the macOS fleet boots a copy of this image as a Tart
# VM. The VM runs the Tuist server release in xcresult-processor mode
# (TUIST_XCRESULT_PROCESSOR_MODE=1, TUIST_WEB=0) under launchd,
# draining the `:process_xcresult` Oban queue.
#
# Layer split: this is Layer 2 on top of
# `ghcr.io/tuist/macos-tahoe-xcode:<major>-<minor>` (built by
# `infra/macos-xcode-image`). Xcode lives in Layer 1 — the NIF
# shells out to `/usr/bin/xcrun xcresulttool`, which only ships in
# full Xcode (not the Command Line Tools), so the base must carry
# the bundle. This layer just lays the Erlang release and the
# launchd unit on top.
#
# Image layout:
#   /opt/tuist/release/        <- Erlang release (built upstream by CI)
#   /opt/tuist/inject-env.sh   <- reads kubelet env mount into /etc/tuist.env
#   /Library/LaunchDaemons/dev.tuist.xcresult-processor.plist
#   /Applications/Xcode_<version>.app <- inherited from Layer 1
#
# Env injection: tart-kubelet stages the Pod's env vars under
# `--dir env:<host-path>:ro`, which the guest sees at
# `/Volumes/My Shared Files/env/tuist.env`. inject-env.sh runs at boot,
# materializes /etc/tuist.env, and launchd's plist sources it.

variable "base_image" {
  type        = string
  description = "Base Tart image (Layer 1: ghcr.io/tuist/macos-tahoe-xcode:<major>-<minor>). Bump to roll onto a new Xcode."
  default     = "ghcr.io/tuist/macos-tahoe-xcode:26-4"
}

variable "output_image" {
  type        = string
  description = "Output image name (e.g. tuist-xcresult-processor)."
  default     = "tuist-xcresult-processor"
}

variable "release_tarball" {
  type        = string
  description = "Path to the Erlang release tarball produced by the upstream macOS release build."
}

variable "cpu_count" {
  type    = number
  default = 4
}

variable "memory_gb" {
  type    = number
  default = 8
}

source "tart-cli" "xcresult_processor" {
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
  sources = ["source.tart-cli.xcresult_processor"]

  provisioner "shell" {
    inline = [
      "echo 'admin' | sudo -S mkdir -p /opt/tuist /etc/tuist",
      "echo 'admin' | sudo -S chown admin:staff /opt/tuist"
    ]
  }

  # Sanity check: xcresulttool has to be reachable before the
  # processor ever calls it. Layer 1 installs Xcode + xcode-select's
  # it; a regression there would silently break ingestion at
  # runtime. Fail loudly here so the image build catches it.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "/usr/bin/xcrun xcresulttool version || (echo 'xcresulttool not reachable — Layer 1 (macos-tahoe-xcode) base image regression' >&2 && exit 1)"
    ]
  }

  provisioner "file" {
    source      = var.release_tarball
    destination = "/tmp/release.tar.gz"
  }

  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "mkdir -p /opt/tuist/release",
      "tar -xzf /tmp/release.tar.gz -C /opt/tuist/release",
      "rm -f /tmp/release.tar.gz",
      "test -x /opt/tuist/release/bin/tuist || (echo 'release missing tuist binary' >&2 && exit 1)"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/inject-env.sh"
    destination = "/tmp/inject-env.sh"
  }

  provisioner "shell" {
    inline = [
      "echo 'admin' | sudo -S install -m 0755 /tmp/inject-env.sh /opt/tuist/inject-env.sh",
      "rm -f /tmp/inject-env.sh"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/launchd.plist"
    destination = "/tmp/dev.tuist.xcresult-processor.plist"
  }

  provisioner "shell" {
    inline = [
      "echo 'admin' | sudo -S install -m 0644 /tmp/dev.tuist.xcresult-processor.plist /Library/LaunchDaemons/dev.tuist.xcresult-processor.plist",
      "rm -f /tmp/dev.tuist.xcresult-processor.plist",
      "echo 'admin' | sudo -S chown root:wheel /Library/LaunchDaemons/dev.tuist.xcresult-processor.plist",
      # Auto-load on boot. We don't `launchctl bootstrap` here — Tart snapshots
      # the disk and the daemon should only start fresh when a VM boots from
      # the image.
      "echo 'admin' | sudo -S mkdir -p /var/log/xcresult-processor",
      "echo 'admin' | sudo -S chown admin:staff /var/log/xcresult-processor"
    ]
  }
}
