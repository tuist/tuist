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
# The image is the per-Pod artifact: every Pod the tart-cri runtime
# schedules onto the macOS fleet boots a copy of this image as a Tart
# VM. The VM runs the Tuist server release in xcresult-processor mode
# (TUIST_XCRESULT_PROCESSOR_MODE=1, TUIST_WEB=0) under launchd,
# draining the `:process_xcresult` Oban queue.
#
# Builds on top of `ghcr.io/tuist/macos-tahoe-xcode-slim:<xcode-version-dashes>`
# (the slim variant from `infra/macos-xcode-image`). Xcode lives in
# the base — the NIF shells out to `/usr/bin/xcrun xcresulttool`,
# which only ships in full Xcode (not the Command Line Tools), so the
# base must carry the bundle. The *slim* base keeps Xcode.app intact
# but drops the simulator runtimes and CI dev tools the runner image
# needs: the processor only *parses* .xcresult bundles, it never runs
# tests. That trims the cold pull enough to clear the Deployment's
# pull deadline on the fleet's 1 GbE NIC (see the slim-variant note
# in `infra/macos-xcode-image/macos-xcode.pkr.hcl`). This build just
# lays the Erlang release and the launchd unit on top.
#
# Image layout:
#   /opt/tuist/release/        <- Erlang release (built upstream by CI)
#   /opt/tuist/inject-env.sh   <- reads kubelet env mount into /etc/tuist.env
#   /Library/LaunchDaemons/dev.tuist.xcresult-processor.plist
#   /Applications/Xcode_<version>.app <- inherited from the base
#
# Env injection: tart-kubelet stages the Pod's env vars under
# `--dir env:<host-path>:ro`, which the guest sees at
# `/Volumes/My Shared Files/env/tuist.env`. inject-env.sh runs at boot,
# materializes /etc/tuist.env, and launchd's plist sources it.

variable "base_image" {
  type        = string
  description = "Base Tart image, e.g. ghcr.io/tuist/macos-tahoe-xcode-slim:26-5 — the slim variant (Xcode, no sims, no CI tools) built by infra/macos-xcode-image with `slim=true`. The release workflow declares the Xcode version inline; the dispatch workflow and local mise task take it as input. Should be at least as new as the newest active runner-image profile (xcresulttool's JSON schema changes across Xcode majors)."
  default     = "ghcr.io/tuist/macos-tahoe-xcode-slim:26-5"
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
  # First boot of a freshly-cloned Tart base image runs macOS first-time
  # setup (kextcache rebuild, Spotlight indexing, APFS expansion,
  # AssetCacheLocator, first-run launchd jobs) which can take 10+ min
  # to reach an SSH-ready state. Cached re-clones (the state of long-
  # lived builder hosts) skip that work and answer in ~30s, which is why
  # tight values held for years on the original Mac mini but timed out
  # on newly-onboarded hosts. 15m gives headroom for the cold path on a
  # cirruslabs Tahoe base; the warm path returns long before then.
  ssh_timeout  = "15m"
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

  # Install tailscale + tailscaled inside the VM. Homebrew's tailscale
  # formula builds the open-source variant from upstream Go source (no
  # GUI app, no .pkg postinstall scripts) — same headless-server shape
  # the Mac mini host bootstrap uses, just compiled locally in the VM
  # rather than cross-compiled in the operator image.
  #
  # tart-cri's vmnet networking gives the VM NAT-style outbound only;
  # without tailscaled inside the VM there is no path from VM userspace
  # to a tailnet CGNAT address (the Mac mini host's tailscaled lives
  # outside the vmnet bridge). Putting tailscaled in the image makes
  # each VM a first-class tailnet member that can dial the Tailscale
  # operator-managed pooler proxy directly. Linux runner microVMs reach
  # in-cluster Services the same way modulo network: their Kata CNI
  # gives them an overlay identity, ours gives them a tailnet identity.
  #
  # `install-system-daemon` lays the canonical
  # /Library/LaunchDaemons/com.tailscale.tailscaled.plist that the
  # tailscaled binary itself ships and load. tailscale-up.sh (run from
  # the xcresult-processor plist below) authenticates against the
  # per-VM auth key the K8s Deployment injects via TAILSCALE_AUTH_KEY.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "/opt/homebrew/bin/brew install tailscale",
      "echo 'admin' | sudo -S /opt/homebrew/bin/tailscaled install-system-daemon",
      "/opt/homebrew/bin/tailscale version"
    ]
  }

  # Sanity check: xcresulttool has to be reachable AND able to parse
  # a real bundle before the processor ever calls it. `version`
  # alone is not enough — the NIF shells out to `xcresulttool get
  # test-results tests`, and a missing private framework in the
  # bundle (the failure mode that would follow from over-trimming
  # Xcode) surfaces only at parse time, not at `version`. The slim
  # base keeps Xcode.app whole specifically to avoid that, so we
  # prove it here: generate a real .xcresult from a throwaway macOS
  # unit test (macOS destination needs no simulator runtime, which
  # the slim base doesn't carry) and run the exact command the NIF
  # uses against it. Fail the build loudly if either step breaks.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "/usr/bin/xcrun xcresulttool version || (echo 'xcresulttool not reachable — slim base image regression' >&2 && exit 1)",
      "WORKDIR=$(mktemp -d)",
      "BUNDLE=$WORKDIR/verify.xcresult",
      "mkdir -p $WORKDIR/Sources/Smoke $WORKDIR/Tests/SmokeTests",
      "cat > $WORKDIR/Package.swift <<'PKG'",
      "// swift-tools-version:5.9",
      "import PackageDescription",
      "let package = Package(",
      "  name: \"Smoke\",",
      "  targets: [",
      "    .target(name: \"Smoke\"),",
      "    .testTarget(name: \"SmokeTests\", dependencies: [\"Smoke\"]),",
      "  ]",
      ")",
      "PKG",
      "cat > $WORKDIR/Sources/Smoke/Smoke.swift <<'SRC'",
      "public func smokeAnswer() -> Int { 42 }",
      "SRC",
      "cat > $WORKDIR/Tests/SmokeTests/SmokeTests.swift <<'TST'",
      "import XCTest",
      "@testable import Smoke",
      "final class SmokeTests: XCTestCase {",
      "  func testSmoke() { XCTAssertEqual(smokeAnswer(), 42) }",
      "}",
      "TST",
      "cd $WORKDIR",
      "xcodebuild test -scheme Smoke -destination 'platform=macOS' -resultBundlePath $BUNDLE",
      "/usr/bin/xcrun xcresulttool get test-results tests --path $BUNDLE > /dev/null || (echo 'xcresulttool could not parse a real .xcresult — slim base is missing something xcresulttool needs at parse time' >&2 && exit 1)",
      "echo 'xcresulttool parsed a real macOS-test .xcresult bundle'",
      "rm -rf $WORKDIR"
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
    source      = "${path.root}/tailscale-up.sh"
    destination = "/tmp/tailscale-up.sh"
  }

  provisioner "shell" {
    inline = [
      "echo 'admin' | sudo -S install -m 0755 /tmp/tailscale-up.sh /opt/tuist/tailscale-up.sh",
      "rm -f /tmp/tailscale-up.sh"
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
