packer {
  required_plugins {
    tart = {
      version = ">= 1.16.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "base_image" {
  type        = string
  description = "Base Tart image from Cirrus Labs (e.g. ghcr.io/cirruslabs/macos-tahoe-xcode:26.4)"
}

variable "output_image" {
  type        = string
  description = "Name for the output image (e.g. tuist-runner-xcode-26.4)"
}

variable "runner_version" {
  type        = string
  default     = "2.325.0"
  description = "GitHub Actions runner version to install"
}

source "tart-cli" "runner" {
  vm_base_name = var.base_image
  vm_name      = var.output_image
  cpu_count    = 4
  memory_gb    = 8
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "120s"
  headless     = true
}

build {
  sources = ["source.tart-cli.runner"]

  provisioner "shell" {
    inline = [
      "echo 'admin' | sudo -S mkdir -p /opt/actions-runner",
      "echo 'admin' | sudo -S chown admin:staff /opt/actions-runner"
    ]
  }

  provisioner "shell" {
    inline = [
      "cd /opt/actions-runner",
      "curl -sL -o actions-runner.tar.gz https://github.com/actions/runner/releases/download/v${var.runner_version}/actions-runner-osx-arm64-${var.runner_version}.tar.gz",
      "tar xzf actions-runner.tar.gz",
      "rm actions-runner.tar.gz",
      "./config.sh --version"
    ]
  }
}
