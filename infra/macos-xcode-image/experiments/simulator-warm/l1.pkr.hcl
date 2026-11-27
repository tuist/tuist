# Experiment: Layer 1 with simulators warmed. Clones a macos-tahoe-xcode base
# (standalone, like the real Layer 1 build), boots each device once as admin,
# and shuts it down. Not used by any release. Driven by
# .github/workflows/simulator-warm-experiment.yml.
packer {
  required_plugins {
    tart = {
      version = ">= 1.16.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "base_image" { type = string }
variable "output_image" { type = string }
variable "devices" { type = list(string) }

source "tart-cli" "l1" {
  vm_base_name = var.base_image
  vm_name      = var.output_image
  cpu_count    = 4
  memory_gb    = 8
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "15m"
  headless     = true
}

build {
  sources = ["source.tart-cli.l1"]

  provisioner "file" {
    source      = "${path.root}/warm.sh"
    destination = "/tmp/warm.sh"
  }

  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "source ~/.zprofile",
      "ls -ld /Users/runner",
      "bash /tmp/warm.sh ${join(" ", [for d in var.devices : "'${d}'"])}",
      "rm -f /tmp/warm.sh",
    ]
  }
}
