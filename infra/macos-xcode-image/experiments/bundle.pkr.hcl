# Experiment: add one Xcode to an existing macos-tahoe-xcode image, so a
# chain of builds produces a multi-Xcode bundle. Not used by any release.
# Driven by .github/workflows/macos-xcode-bundle-experiment.yml.
packer {
  required_plugins {
    tart = {
      version = ">= 1.16.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "base_image" { type = string }
variable "stacked" {
  type    = bool
  default = false
}
variable "output_image" { type = string }
variable "xcode_xip_path" { type = string }
variable "xcode_version" { type = string }
variable "disk_size_gb" {
  type    = number
  default = 260
}

source "tart-cli" "bundle" {
  vm_base_name = var.base_image
  vm_name      = var.output_image
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = var.disk_size_gb
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "120s"
  headless     = true
  # A stacked VM has no disk.img for the plugin to edit (see infra/runner-image/runner.pkr.hcl).
  recovery_partition = var.stacked ? "keep" : "delete"
}

build {
  sources = ["source.tart-cli.bundle"]

  # Claim the space disk_size_gb added (same loop as infra/runner-image/runner.pkr.hcl).
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "store=$(diskutil info / | awk -F': *' '/APFS Physical Store/ { print $2 }')",
      "disk=$${store%s*}",
      "size() { diskutil info -plist \"$1\" | plutil -extract TotalSize raw -; }",
      "printf 'y\\n' | sudo diskutil repairDisk \"$disk\"",
      "for attempt in 1 2 3 4 5; do sudo diskutil apfs resizeContainer \"$store\" 0 2>&1 || true; unclaimed=$(( $(size \"$disk\") - $(size \"$store\") )); echo \"resizeContainer attempt $attempt: $(size \"$store\") of $(size \"$disk\") bytes\"; [ \"$unclaimed\" -gt 5000000000 ] || break; [ \"$attempt\" -lt 5 ] || exit 1; sleep 15; done",
      "echo BUNDLE-EXP before: $(df -k / | awk 'NR==2 {print $3}') KiB used",
    ]
  }

  provisioner "file" {
    source      = var.xcode_xip_path
    destination = "/Users/admin/Downloads/Xcode.xip"
  }

  # Same install steps as ../macos-xcode.pkr.hcl.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "source ~/.zprofile",
      "brew list xcodes >/dev/null 2>&1 || brew install xcodes aria2",
      "echo 'admin' | sudo -S xcodes install ${var.xcode_version} --experimental-unxip --path /Users/admin/Downloads/Xcode.xip --select --empty-trash",
      "INSTALLED_PATH=$(xcodes select -p)",
      "APP_DIR=$(dirname \"$(dirname \"$INSTALLED_PATH\")\")",
      "sudo mv \"$APP_DIR\" /Applications/Xcode_${var.xcode_version}.app",
      "sudo xcode-select -s /Applications/Xcode_${var.xcode_version}.app",
      "sudo xcodebuild -license accept",
      "sudo xcodebuild -runFirstLaunch",
      "for i in 1 2 3 4 5; do sudo xcodebuild -downloadAllPlatforms && break; [ $i -lt 5 ] || exit 1; echo \"downloadAllPlatforms failed, retry $i\" >&2; sleep 60; done",
      "XCODE_BUILD=$(xcodebuild -version | awk '/^Build version/ {print $3}')",
      "INDEX=$(mktemp)",
      "curl -fsSL https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex -o \"$INDEX\"",
      "METAL_BUILD=''",
      "for i in $(seq 0 $(($(plutil -extract xcodeToOtherDownloadablesMappings raw -o - \"$INDEX\") - 1))); do if [ \"$(plutil -extract xcodeToOtherDownloadablesMappings.$i.assetType raw -o - \"$INDEX\")\" = metalToolchain ] && [ \"$(plutil -extract xcodeToOtherDownloadablesMappings.$i.xcodeBuildUpdate raw -o - \"$INDEX\")\" = \"$XCODE_BUILD\" ]; then METAL_BUILD=$(plutil -extract xcodeToOtherDownloadablesMappings.$i.assetBuildUpdate raw -o - \"$INDEX\"); fi; done",
      "rm -f \"$INDEX\"",
      "[ -n \"$METAL_BUILD\" ] && xcodebuild -downloadComponent MetalToolchain -buildVersion \"$METAL_BUILD\"",
      "rm -f /Users/admin/Downloads/Xcode.xip",
      "/usr/bin/xcrun xcresulttool version",
    ]
  }

  provisioner "shell" {
    inline = [
      "echo BUNDLE-EXP after: $(df -k / | awk 'NR==2 {print $3}') KiB used",
      "for x in /Applications/Xcode_*.app; do [ -L \"$x\" ] || echo BUNDLE-EXP app $x $(sudo du -sk \"$x\" | cut -f1) KiB; done",
      "echo BUNDLE-EXP simulators $(sudo du -sk /Library/Developer/CoreSimulator 2>/dev/null | cut -f1) KiB",
      "xcrun simctl runtime list || true",
    ]
  }
}
