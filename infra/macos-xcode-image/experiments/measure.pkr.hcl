# Experiment: boot a clone of an image and run measure.sh in it. The
# output VM is deleted by the workflow; nothing is pushed.
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

source "tart-cli" "measure" {
  vm_base_name = var.base_image
  vm_name      = var.output_image
  cpu_count    = 6
  memory_gb    = 14
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "300s"
  headless     = true
}

build {
  sources = ["source.tart-cli.measure"]

  provisioner "file" {
    source      = "${path.root}/measure.sh"
    destination = "/tmp/measure.sh"
  }

  provisioner "shell" {
    inline = ["bash /tmp/measure.sh"]
  }
}
