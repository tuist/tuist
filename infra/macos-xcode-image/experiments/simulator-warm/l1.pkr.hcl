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
variable "cpu_count" {
  type    = number
  default = 8
}
variable "memory_gb" {
  type    = number
  default = 16
}
variable "parallel" {
  type    = bool
  default = false
}

source "tart-cli" "l1" {
  vm_base_name = var.base_image
  vm_name      = var.output_image
  cpu_count    = var.cpu_count
  memory_gb    = var.memory_gb
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
      "WARM_PARALLEL=${var.parallel ? 1 : 0} bash /tmp/warm.sh ${join(" ", [for d in var.devices : "'${d}'"])}",
      "rm -f /tmp/warm.sh",
    ]
  }
}
