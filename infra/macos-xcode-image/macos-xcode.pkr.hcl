packer {
  required_plugins {
    tart = {
      version = ">= 1.16.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

# Build the Tart VM image that bundles macOS + a *set* of Xcode
# versions + the dev tools customer iOS/macOS workflows depend on.
# This is our in-house replacement for
# `ghcr.io/cirruslabs/macos-tahoe-xcode:N` — the goal is to be on
# a new Xcode the day Apple ships it, and to co-install older
# Xcodes so customer workflows that pin `.xcode-version=26.0`
# don't pay a per-job install cost.
#
# Multi-Xcode model:
#   - `xcode_versions` lists every Xcode baked into the image,
#     newest first. The first element is the *default* — what
#     `xcode-select` activates, what `/usr/bin/xcrun` resolves
#     against, and what the major-minor alias points at.
#   - All listed versions land at /Applications/Xcode_<version>.app
#     (underscore form, matching GitHub-hosted runner images).
#     Customer workflows pick a specific Xcode via xcode-select,
#     DEVELOPER_DIR, or .xcode-version + an action like
#     maxim-lobanov/setup-xcode.
#
# Cost profile (~6 Xcode versions, full simulator runtimes for the
# default): ~3 hours to build, ~250 GB image. Per-host pull on a
# cold runner is the dominant ongoing cost — bundle into the
# bare-metal Mac mini base image where possible.
#
# This image is the *base layer*. Two downstream images inherit
# from it and add the Tuist-specific runtime:
#   - `ghcr.io/tuist/tuist-runner` (infra/runner-image) — adds the
#     GitHub Actions runner agent + dispatch loop.
#   - `ghcr.io/tuist/tuist-xcresult-processor` (infra/xcresult-processor-image)
#     — adds the Erlang release that drains `:process_xcresult`.
#
# Splitting the slow Xcode-install (~30 min per version) out of
# the per-release image builds means a `feat(runner-image): ...`
# commit doesn't pay the install tax on every CI rebuild; it just
# re-clones this image and lays the runner agent on top in ~2 min.
#
# Inputs come from the image-build workflow on the bare-metal Mac
# mini, which has a logged-in xcodes session in its login keychain
# (`xcodes signin <apple-id>` run by a maintainer once per quarter
# — see infra/macos-xcode-image/AGENTS.md). The workflow runs
# `xcodes download <version>` for each version against
# developer.apple.com using that session and stages every .xip in
# a single directory passed here.

variable "base_image" {
  type        = string
  description = "Base Tart image. Defaults to Cirrus's vanilla macOS+brew base; we layer Xcode + dev tools on top."
  default     = "ghcr.io/cirruslabs/macos-tahoe-base:latest"
}

variable "output_image" {
  type        = string
  description = "Output image name. The push tag uses the *default* Xcode's major-minor (e.g. `:26-5` when the first xcode_versions entry is 26.5.0)."
  default     = "macos-tahoe-xcode"
}

variable "xcode_versions" {
  type        = list(string)
  description = "Xcode versions to install, in order. The FIRST element is the default (xcode-select target). Subsequent versions are co-installed at /Applications/Xcode_<version>.app so customer workflows pinning older Xcodes don't pay an install cost at job time."

  validation {
    condition     = length(var.xcode_versions) >= 1
    error_message = "Variable xcode_versions must contain at least one version."
  }
}

variable "xcode_xip_dir" {
  type        = string
  description = "Host directory containing one .xip per version, named Xcode-<version>*.xip (xcodes' default naming). The whole directory is copied into the VM."
}

variable "cpu_count" {
  type    = number
  default = 4
}

variable "memory_gb" {
  type    = number
  default = 8
}

# Each Xcode bundle is ~40 GB on disk, plus simulator runtimes
# (~60 GB shared across versions via /Library/Developer/CoreSimulator)
# and the rest of the OS. 350 GB leaves headroom for ~6 Xcodes +
# downloadAllPlatforms + the brew dev-tool layer. Tart's disk is
# sparse, so the on-disk size reflects actual usage — but the
# value bounds what the guest can fill.
variable "disk_size_gb" {
  type    = number
  default = 350
}

locals {
  # First element of xcode_versions drives the image identity: the
  # tag pushed to GHCR, the xcode-select target, the major-minor
  # alias. Co-installed older Xcodes are addressable by their full
  # /Applications/Xcode_<version>.app path but don't shape the tag.
  default_xcode_version = var.xcode_versions[0]
  default_major_minor   = regex("^[0-9]+\\.[0-9]+", local.default_xcode_version)
}

source "tart-cli" "macos_xcode" {
  vm_base_name = var.base_image
  vm_name      = var.output_image
  cpu_count    = var.cpu_count
  memory_gb    = var.memory_gb
  disk_size_gb = var.disk_size_gb
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "120s"
  headless     = true
}

build {
  sources = ["source.tart-cli.macos_xcode"]

  # Install xcodes + aria2 (xcodes' parallel-download backend;
  # signature verification on local .xips also imports aria2).
  # macos-tahoe-base wires brew's shellenv into ~/.zprofile so
  # `source` here is what makes `brew` reachable on the next line.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "source ~/.zprofile",
      "brew install xcodes aria2"
    ]
  }

  # Stage every .xip inside the VM under one directory. Packer's
  # `file` provisioner copies the directory's contents recursively
  # when the source path ends with `/`. The host downloads each
  # version's .xip into xcode_xip_dir before invoking Packer (see
  # the macos-xcode-image.yml workflow's download loop).
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "mkdir -p /Users/admin/Downloads/xcode-xips"
    ]
  }

  provisioner "file" {
    source      = "${var.xcode_xip_dir}/"
    destination = "/Users/admin/Downloads/xcode-xips/"
  }

  # Loop install via the helper script. Keeping the per-version
  # logic out of an inline-string-array dodges the worst of HCL's
  # `${...}` vs shell `${...}` quoting fight.
  provisioner "file" {
    source      = "${path.root}/install-xcodes.sh"
    destination = "/tmp/install-xcodes.sh"
  }

  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "chmod +x /tmp/install-xcodes.sh",
      "/tmp/install-xcodes.sh ${join(" ", var.xcode_versions)}",
      "rm /tmp/install-xcodes.sh",
      "echo 'admin' | sudo -S rm -rf /Users/admin/Downloads/xcode-xips"
    ]
  }

  # Major-minor alias for the *default* Xcode so repos pinning
  # either `.xcode-version=26.5` or `.xcode-version=26.5.0` resolve
  # to the same bundle. Co-installed older Xcodes don't get a
  # major-minor alias: customers pinning, say, `26.4` would resolve
  # the patch-form bundle directly (e.g. /Applications/Xcode_26.4.1.app).
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "if [ \"${local.default_xcode_version}\" != \"${local.default_major_minor}\" ]; then echo 'admin' | sudo -S ln -sfn /Applications/Xcode_${local.default_xcode_version}.app /Applications/Xcode_${local.default_major_minor}.app; fi",
      "ls -1d /Applications/Xcode_*.app"
    ]
  }

  # Activate the default Xcode + run the per-Xcode initialization
  # tasks against it. We do this *once* against the default rather
  # than per-Xcode because:
  #  - `xcodebuild -license accept` is per-version but accepting
  #    the newest version's license also satisfies older ones.
  #  - `xcodebuild -runFirstLaunch` installs / repairs system-wide
  #    components (CommandLineTools symlinks, MobileDevice
  #    framework) that older Xcodes share.
  #  - `xcodebuild -downloadAllPlatforms` writes simulator runtimes
  #    into /Library/Developer/CoreSimulator/Profiles/Runtimes/,
  #    which is system-wide and shared across every co-installed
  #    Xcode.
  # Trade-off: customer workflows pinning an older Xcode + needing
  # a specific older simulator runtime (e.g. iOS 17.0 against
  # Xcode 15) would have to download that runtime at job time.
  # The default covers the common case — newest sims, newest
  # Xcode — without bloating the image by a factor of N.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "echo 'admin' | sudo -S xcode-select -s /Applications/Xcode_${local.default_xcode_version}.app",
      "sudo xcodebuild -license accept",
      "sudo xcodebuild -runFirstLaunch",
      "sudo xcodebuild -downloadAllPlatforms",
      "/usr/bin/xcrun xcresulttool version || (echo 'xcresulttool not reachable after install' >&2 && exit 1)"
    ]
  }

  # Developer tooling customer workflows expect on a GitHub-Actions-
  # parity macOS image. macos-tahoe-base ships brew + mise + gh +
  # git-lfs + jq + yq + node + yarn + rbenv + awscli; the install
  # list below covers the gap to GH-hosted / Cirrus xcode's tooling
  # layer.
  #
  # fastlane + cocoapods come from brew rather than gem (the Cirrus
  # xcode template uses rbenv + gem install pinned to Ruby 3.3.10
  # because fastlane breaks on 3.4+). Brew's formulae bundle their
  # own Ruby, sidestepping the version pin — simpler, and what
  # GitHub-hosted images now do too.
  #
  # We intentionally do *not* preinstall the Tuist CLI here.
  # Customer workflows install it themselves via mise / brew so the
  # version is theirs to pin; baking it in just creates a stale
  # default that drifts behind every Tuist release.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "source ~/.zprofile",
      "brew install libimobiledevice ideviceinstaller ios-deploy carthage",
      "brew install xcbeautify swiftformat swiftlint swiftgen licenseplist mint",
      "brew install fastlane cocoapods"
    ]
  }

  # Apple WWDR + Developer ID intermediate certificates. Customer
  # workflows that sign/verify with developer-account-issued certs
  # need these in the system trust store. Installed via the same
  # swift helper the GitHub-hosted macOS image uses so the trust
  # path matches.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "source ~/.zprofile",
      "cd /tmp",
      "curl -fsSL -o AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer",
      "curl -fsSL -o DeveloperIDG2CA.cer https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer",
      "curl -fsSL -o add-certificate.swift https://raw.githubusercontent.com/actions/runner-images/fb3b6fd69957772c1596848e2daaec69eabca1bb/images/macos/provision/configuration/add-certificate.swift",
      "swiftc -suppress-warnings add-certificate.swift",
      "echo 'admin' | sudo -S ./add-certificate AppleWWDRCAG3.cer",
      "sudo ./add-certificate DeveloperIDG2CA.cer",
      "rm -f add-certificate add-certificate.swift AppleWWDRCAG3.cer DeveloperIDG2CA.cer"
    ]
  }

  # Sanity check: every tool a downstream Layer 2 image (or a
  # customer workflow) expects has to be reachable from admin's
  # login shell. /Users/runner is a symlink to /Users/admin in
  # macos-tahoe-base, so the runner user the runner-image layer
  # creates will see the same .zprofile and resolve the same tools.
  # We also verify every co-installed Xcode bundle landed at its
  # expected path so a botched install fails the build instead of
  # surfacing at customer-job time.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "/bin/zsh -lc 'for tool in brew mise gh git-lfs jq yq xcodes xcrun xcresulttool swiftlint swiftformat xcbeautify fastlane pod carthage mint idevice_id ideviceinstaller ios-deploy; do command -v \"$tool\" >/dev/null 2>&1 || { echo \"sanity check: $tool missing from PATH\" >&2; exit 1; }; done'",
      "/bin/zsh -lc '/usr/bin/xcrun xcresulttool version'",
      "for v in ${join(" ", var.xcode_versions)}; do test -d /Applications/Xcode_$v.app || { echo \"sanity check: /Applications/Xcode_$v.app missing\" >&2; exit 1; }; done",
      "echo '=== Installed Xcode bundles ===' && ls -1d /Applications/Xcode_*.app"
    ]
  }
}
