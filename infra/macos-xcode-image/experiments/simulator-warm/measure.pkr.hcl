# Experiment: clone a Layer 2 build with a new serial (`serial-tart/` on PATH
# turns the plugin's `tart clone` into clone + `tart set --random-serial`, as
# tart-kubelet does for runner VMs), boot it, and run measure.sh as runner.
# Not used by any release. Driven by .github/workflows/simulator-warm-experiment.yml.
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
variable "label" { type = string }
variable "devices" { type = list(string) }

source "tart-cli" "measure" {
  vm_base_name       = var.base_image
  vm_name            = var.output_image
  cpu_count          = 4
  memory_gb          = 8
  ssh_username       = "admin"
  ssh_password       = "admin"
  ssh_timeout        = "15m"
  headless           = true
  recovery_partition = "keep"
}

build {
  sources = ["source.tart-cli.measure"]

  provisioner "file" {
    source      = "${path.root}/measure.sh"
    destination = "/tmp/measure.sh"
  }

  provisioner "shell" {
    valid_exit_codes = [0, 1]
    inline = [
      "chmod 0755 /tmp/measure.sh",
      "echo 'admin' | sudo -S launchctl asuser \"$(id -u runner)\" sudo -u runner -H /bin/zsh -lc \"/tmp/measure.sh ${var.label} ${join(" ", [for d in var.devices : "'${d}'"])}\"",
    ]
  }
}
