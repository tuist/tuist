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
# The image is the per-Pod artifact in the new architecture: every Pod the
# Virtual Kubelet provider schedules onto the macOS fleet boots a copy of
# this image as a Tart VM. The VM runs the Tuist server release in
# xcresult-processor mode (TUIST_XCRESULT_PROCESSOR_MODE=1, TUIST_WEB=0)
# under launchd, draining the `:process_xcresult` Oban queue.
#
# Image layout:
#   /opt/tuist/release/        <- Erlang release (built upstream by CI)
#   /opt/tuist/inject-env.sh   <- reads VM custom data into /etc/tuist.env
#   /Library/LaunchDaemons/dev.tuist.xcresult-processor.plist
#
# Env injection: Orchard passes per-VM env vars (MASTER_KEY, DATABASE_URL,
# TUIST_DEPLOY_ENV) via Tart's custom-data mechanism. inject-env.sh runs
# at boot, materializes /etc/tuist.env, and launchd's plist sources it.

variable "base_image" {
  type        = string
  description = "Base Tart image. Defaults to Cirrus Labs' macOS+Xcode image so xcresulttool is preinstalled."
  default     = "ghcr.io/cirruslabs/macos-tahoe-xcode:26.0"
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
