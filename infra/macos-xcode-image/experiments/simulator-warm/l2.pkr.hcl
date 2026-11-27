# Experiment: a minimal stacked Layer 2 with the steps of
# infra/runner-image/runner.pkr.hcl that touch simulators: recreate `runner`,
# reboot, re-register the runtimes as disk images, reboot. `variant` picks what
# happens to the simulator device set:
#   control  nothing (today's image)
#   mv       move admin's device set, warmed in Layer 1, into runner's home
#   warm     warm the devices as runner here, after re-registration
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
variable "variant" { type = string }
variable "devices" { type = list(string) }

source "tart-cli" "l2" {
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
  sources = ["source.tart-cli.l2"]

  # Same user recreation as runner.pkr.hcl. /Users/runner is a symlink to
  # /Users/admin in the base, so `rm -rf` drops only the link.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "echo 'admin' | sudo -S rm -rf /Users/runner",
      "sudo sysadminctl -addUser runner -fullName 'GitHub Actions Runner' -password runner -admin",
      "if [ '${var.variant}' = mv ]; then sudo mkdir -p /Users/runner/Library/Developer && sudo mv /Users/admin/Library/Developer/CoreSimulator /Users/runner/Library/Developer/CoreSimulator && sudo chown -R runner:staff /Users/runner/Library && echo \"SIMWARM moved $(sudo du -sh /Users/runner/Library/Developer/CoreSimulator | cut -f1)\"; fi",
    ]
  }

  provisioner "file" {
    source      = "${path.root}/reregister-runtimes.sh"
    destination = "/tmp/reregister-runtimes.sh"
  }

  provisioner "file" {
    source      = "${path.root}/warm.sh"
    destination = "/tmp/warm.sh"
  }

  provisioner "shell" {
    expect_disconnect = true
    skip_clean        = true
    inline = [
      "sysctl -n kern.boottime > /var/tmp/simwarm-boottime",
      "(sleep 2; sudo shutdown -r now) >/dev/null 2>&1 &",
    ]
  }

  provisioner "shell" {
    pause_before = "45s"
    inline = [
      "set -euo pipefail",
      "[ \"$(sysctl -n kern.boottime)\" != \"$(cat /var/tmp/simwarm-boottime)\" ] || { echo 'connected before the reboot' >&2; exit 1; }",
      "echo 'admin' | sudo -S true",
      "bash /tmp/reregister-runtimes.sh",
      "sysctl -n kern.boottime > /var/tmp/simwarm-boottime",
      "(sleep 2; sudo shutdown -r now) >/dev/null 2>&1 &",
    ]
    expect_disconnect = true
    skip_clean        = true
  }

  provisioner "shell" {
    pause_before = "45s"
    inline = [
      "set -euo pipefail",
      "[ \"$(sysctl -n kern.boottime)\" != \"$(cat /var/tmp/simwarm-boottime)\" ] || { echo 'connected before the reboot' >&2; exit 1; }",
      "rm -f /var/tmp/simwarm-boottime",
      "echo 'admin' | sudo -S true",
      "if sudo plutil -p /Library/Developer/CoreSimulator/Images/images.plist 2>/dev/null | grep personalizeAndMountAsCryptex >/dev/null; then echo 'a simulator runtime is a cryptex again after the reboot' >&2; exit 1; fi",
      "chmod 0755 /tmp/warm.sh",
      "if [ '${var.variant}' = warm ]; then sudo launchctl asuser \"$(id -u runner)\" sudo -u runner -H /bin/zsh -lc \"/tmp/warm.sh ${join(" ", [for d in var.devices : "'${d}'"])}\"; fi",
      "sudo rm -f /tmp/warm.sh /tmp/reregister-runtimes.sh",
      "echo \"SIMWARM ${var.variant} runner device set $(sudo du -sh /Users/runner/Library/Developer/CoreSimulator 2>/dev/null | cut -f1)\"",
    ]
  }
}
