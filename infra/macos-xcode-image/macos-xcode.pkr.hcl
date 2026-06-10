packer {
  required_plugins {
    tart = {
      version = ">= 1.16.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

# Build the Tart VM image that bundles macOS + a single Xcode +
# the dev tools customer iOS/macOS workflows depend on. This is
# our in-house replacement for `ghcr.io/cirruslabs/macos-tahoe-xcode:N`
# — the goal is to be on a new Xcode the day Apple ships it
# instead of waiting for Cirrus's catalog to catch up.
#
# Model: one Xcode per image, profile-selectable downstream.
# Each image holds exactly one Xcode at `/Applications/Xcode_<version>.app`,
# the active developer dir for `xcrun`. When the customer-facing
# fleet eventually exposes a runner-profile picker (`runs-on:
# tuist-macos-xcode-26-5`, "Tahoe with Xcode 26.4.x", etc.), each
# profile maps onto a single image variant produced here. This
# mirrors Namespace's per-profile model; GitHub-hosted bakes ~6
# Xcodes into one giant image, which we explicitly didn't want
# because the customer's choice happens at job-routing time, not
# at xcode-select time.
#
# Tag derivation: dot-separated `xcode_version` with dashes.
#   - 26.5     → :26-5      (no patch released yet)
#   - 26.4.1   → :26-4-1
#   - 26.0.1   → :26-0-1
# When the version carries a patch component, we also lay down
# `/Applications/Xcode_<major>.<minor>.app` as a symlink to the
# real patch bundle so repos pinning the major-minor form in
# `.xcode-version` resolve to the patched Xcode. Versions with
# only two components don't get an extra alias (the path is
# already in major-minor form).
#
# This image is the *base layer*. Two downstream images inherit
# from it and add the Tuist-specific runtime:
#   - `ghcr.io/tuist/tuist-runner` (infra/runner-image) — adds the
#     GitHub Actions runner agent + dispatch loop.
#   - `ghcr.io/tuist/tuist-xcresult-processor` (infra/xcresult-processor-image)
#     — adds the Erlang release that drains `:process_xcresult`.
#
# Splitting the slow Xcode install (~30 min) out of the per-release
# image builds means a `feat(runner-image): ...` commit doesn't pay
# the Xcode-install tax on every CI rebuild; it just re-clones
# this image and lays the runner agent on top in ~2 min.
#
# Slim variant (`slim = true`, pushed as `macos-tahoe-xcode-slim`).
# The xcresult-processor only *parses* .xcresult bundles — it never
# runs tests — so it needs Xcode (for `xcresulttool`) but neither
# the simulator runtimes nor the CI dev-tool grab-bag the runner
# image carries. The slim variant keeps `Xcode.app` fully intact
# (xcresulttool's framework closure must stay complete) but skips
# `-downloadAllPlatforms`, the brew tool layer, and the signing
# certs. That's the difference between a ~60 GB and a ~50 GB pull,
# which matters because the processor's Mac mini fleet sits behind
# a fixed 1 GbE NIC (~125 MB/s) and its Deployment has a pull
# deadline a fat image blows past. Runners MUST stay on the full
# image (customer CI needs the sims + tools); slim is processor-only.
#
# Inputs come from the image-build workflow on the bare-metal Mac
# mini. The workflow pulls Xcode_<version>.xip from our in-house
# mirror at `ghcr.io/tuist/xcode-xips:<version>`, populated by
# `mise run xcode-mirror:upload <version>` on a maintainer's Mac
# (`infra/macos-xcode-image/AGENTS.md` for the runbook). Nothing
# in this template talks to developer.apple.com.

variable "base_image" {
  type        = string
  description = "Base Tart image. Defaults to Cirrus's vanilla macOS+brew base; we layer Xcode + dev tools on top."
  default     = "ghcr.io/cirruslabs/macos-tahoe-base:latest"
}

variable "output_image" {
  type        = string
  description = "Output image name. The push tag uses xcode_version with dots → dashes (e.g. `:26-4-1`)."
  default     = "macos-tahoe-xcode"
}

variable "xcode_xip_path" {
  type        = string
  description = "Host path to the Xcode_<version>.xip downloaded by `xcodes download` on the build host."
}

variable "xcode_version" {
  type        = string
  description = "Xcode version installed from the .xip (e.g. \"26.4.1\" or \"26.5\"). Drives the bundle path /Applications/Xcode_<version>.app and the major-minor alias (only when the version has a patch component)."
}

variable "slim" {
  type        = bool
  default     = false
  description = "Build the slim variant (xcresult-processor base): full Xcode for xcresulttool, but no simulator runtimes, no CI dev tools, no signing certs. Pushed as macos-tahoe-xcode-slim. Leave false for the runner-image base."
}

variable "cpu_count" {
  type    = number
  default = 4
}

variable "memory_gb" {
  type    = number
  default = 8
}

# macos-tahoe-base ships with a 50 GB disk. Full Xcode is ~40 GB,
# the brew dev-tool layer adds another ~5 GB, and `xcodebuild
# -downloadAllPlatforms` pulls ~15 GB of simulator runtimes.
# 140 GB matches what Cirrus provisions for their equivalent image
# and leaves headroom for the downstream runner-image /
# xcresult-processor builds + customer DerivedData when the image
# is in service. The slim variant skips the sims + dev tools, so
# `local.disk_size_gb` trims it to 100 GB — still room for the
# .xip (~12 GB) staged alongside the extracted Xcode (~40 GB) on
# top of the macOS base during the build.
variable "disk_size_gb" {
  type    = number
  default = 140
}

locals {
  # Major-minor form of xcode_version, e.g. "26.4.1" → "26.4".
  # Used for the alias `/Applications/Xcode_<major-minor>.app`
  # when xcode_version has three components. When xcode_version
  # is already in major-minor form ("26.5"), the alias path
  # equals the real path so the symlink step is skipped at build
  # time.
  xcode_major_minor = regex("^[0-9]+\\.[0-9]+", var.xcode_version)

  # Slim drops the sims (~15 GB) + dev tools (~5 GB), so it doesn't
  # need the full 140 GB envelope — 100 GB covers macOS + Xcode +
  # the .xip staged during install with headroom.
  disk_size_gb = var.slim ? 100 : var.disk_size_gb

  # Final-sanity tool set. The slim variant doesn't install the CI
  # grab-bag, so it only asserts the base tools (inherited from
  # macos-tahoe-base) plus xcrun; xcresulttool itself is checked
  # separately below.
  sanity_tools = var.slim ? "brew mise gh git-lfs jq yq xcodes xcrun" : "brew mise gh git-lfs jq yq xcodes xcrun swiftlint swiftformat xcbeautify fastlane pod carthage mint idevice_id ideviceinstaller ios-deploy"
}

source "tart-cli" "macos_xcode" {
  vm_base_name = var.base_image
  vm_name      = var.output_image
  cpu_count    = var.cpu_count
  memory_gb    = var.memory_gb
  disk_size_gb = local.disk_size_gb
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "120s"
  headless     = true
}

build {
  sources = ["source.tart-cli.macos_xcode"]

  # Install xcodes + aria2 (xcodes' parallel-download backend;
  # signature verification on local .xips also imports aria2).
  # macos-tahoe-base wires brew's shellenv into ~/.zprofile, so
  # `source` here is what makes `brew` reachable on the next line.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "source ~/.zprofile",
      "brew install xcodes aria2"
    ]
  }

  # Stage the .xip inside the VM. SSH transfer of a ~10 GB blob
  # over Tart's loopback runs in a few minutes on the bare-metal
  # builder.
  provisioner "file" {
    source      = var.xcode_xip_path
    destination = "/Users/admin/Downloads/Xcode.xip"
  }

  # Install Xcode from the staged .xip. `--experimental-unxip`
  # swaps the single-threaded `xip` extractor for a parallel one —
  # the slow phase of any Xcode install. `--select` switches the
  # active developer dir so /usr/bin/xcrun resolves against the
  # new bundle. `--empty-trash` reclaims the .xip from the trash
  # bin (xcodes moves the source .xip there on success, which
  # without this flag blows past the disk budget on a re-run).
  #
  # `xcodebuild -runFirstLaunch` accepts the bundled platform SDK
  # licenses and installs simulator runtime stubs.
  # `-downloadAllPlatforms` pulls iOS / tvOS / watchOS / visionOS
  # simulator runtimes at image build so the first job on a fresh
  # VM doesn't pay the runtime download cost. Matches what
  # GitHub-hosted's macos-26 image ships. Skipped for slim: the
  # xcresult-processor never runs tests, so it has no use for the
  # sim runtimes, and they're the single biggest removable chunk
  # of the image's pull weight.
  #
  # `echo 'admin' | sudo -S` on the first sudo call primes the
  # admin sudo timestamp cache; subsequent bare `sudo` calls in
  # the same SSH session ride that cache. Packer shell provisioners
  # are non-interactive — without this, the first `sudo xcodes
  # install` would hang on a password prompt.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "source ~/.zprofile",
      "echo 'admin' | sudo -S xcodes install ${var.xcode_version} --experimental-unxip --path /Users/admin/Downloads/Xcode.xip --select --empty-trash",
      "INSTALLED_PATH=$(xcodes select -p)",
      "CONTENTS_DIR=$(dirname \"$INSTALLED_PATH\")",
      "APP_DIR=$(dirname \"$CONTENTS_DIR\")",
      "sudo mv \"$APP_DIR\" /Applications/Xcode_${var.xcode_version}.app",
      "sudo xcode-select -s /Applications/Xcode_${var.xcode_version}.app",
      "sudo xcodebuild -license accept",
      "sudo xcodebuild -runFirstLaunch",
      "if [ \"${var.slim}\" != \"true\" ]; then sudo xcodebuild -downloadAllPlatforms; else echo 'slim: skipping simulator runtime download'; fi",
      "/usr/bin/xcrun xcresulttool version || (echo 'xcresulttool not reachable after install' >&2 && exit 1)"
    ]
  }

  # Major-minor alias for repos pinning either `.xcode-version=
  # 26.4` or `.xcode-version=26.4.1` — both resolve to the same
  # bundle. Skipped when xcode_version is already in major-minor
  # form (e.g. "26.5"), where the alias path equals the real path.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "if [ \"${var.xcode_version}\" != \"${local.xcode_major_minor}\" ]; then echo 'admin' | sudo -S ln -sfn /Applications/Xcode_${var.xcode_version}.app /Applications/Xcode_${local.xcode_major_minor}.app; fi",
      "ls -lhd /Applications/Xcode_${var.xcode_version}*.app /Applications/Xcode_${local.xcode_major_minor}*.app 2>/dev/null || true"
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
  # Customer workflows install it themselves via mise / brew so
  # the version is theirs to pin; baking it in just creates a
  # stale default that drifts behind every Tuist release.
  #
  # Skipped for slim: this grab-bag exists for customer CI on the
  # runner image. The xcresult-processor only parses bundles, so it
  # carries none of it.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "if [ \"${var.slim}\" = \"true\" ]; then echo 'slim: skipping CI dev tools'; exit 0; fi",
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
  #
  # Skipped for slim: xcresulttool reads bundles off disk and never
  # touches the signing trust store, so the processor doesn't need
  # these.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "if [ \"${var.slim}\" = \"true\" ]; then echo 'slim: skipping signing certs'; exit 0; fi",
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

  # Sanity check: every tool a downstream image (runner-image,
  # xcresult-processor) or customer workflow expects has to be
  # reachable from admin's login shell. /Users/runner is a symlink
  # to /Users/admin in macos-tahoe-base, so the runner user the
  # runner-image build creates will see the same .zprofile and
  # resolve the same tools.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "/bin/zsh -lc 'for tool in ${local.sanity_tools}; do command -v \"$tool\" >/dev/null 2>&1 || { echo \"sanity check: $tool missing from PATH\" >&2; exit 1; }; done'",
      # xcresulttool lives inside the Xcode bundle and isn't on
      # $PATH directly — it's reached via `xcrun xcresulttool`.
      # The `command -v` loop above checks `xcrun`'s presence;
      # the line below proves `xcrun` can actually resolve
      # xcresulttool against the active developer dir.
      "/bin/zsh -lc '/usr/bin/xcrun xcresulttool version'"
    ]
  }
}
