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
# Builds on top of `ghcr.io/tuist/macos-tahoe-xcode:<xcode-version-dashes>`
# (built by `infra/macos-xcode-image`). Xcode lives in the base —
# the NIF shells out to `/usr/bin/xcrun xcresulttool`, which only
# ships in full Xcode (not the Command Line Tools), so the base
# must carry the bundle. This build lays Tailscale, the boot scripts
# and the launchd unit on top. The server release is not part of the
# image: fetch-release.sh downloads the one the Pod pins at boot.
#
# Image layout:
#   /opt/tuist/release/          <- empty; fetch-release.sh installs the release here
#   /opt/tuist/inject-env.sh     <- reads kubelet env mount into /etc/tuist.env
#   /opt/tuist/fetch-release.sh  <- installs the pinned server release
#   /Library/LaunchDaemons/dev.tuist.xcresult-processor.plist
#   /Applications/Xcode_<version>.app <- inherited from the base
#
# Env injection: tart-kubelet stages the Pod's env vars under
# `--dir env:<host-path>:ro`, which the guest sees at
# `/Volumes/My Shared Files/env/tuist.env`. inject-env.sh runs at boot,
# materializes /etc/tuist.env, and launchd's plist sources it.

variable "base_image" {
  type        = string
  description = "Base Tart image, e.g. ghcr.io/tuist/macos-tahoe-xcode:26-5. The release workflow declares the Xcode version inline; the dispatch workflow and local mise task take it as input. Should be at least as new as the newest active runner-image profile (xcresulttool's JSON schema changes across Xcode majors)."
  default     = "ghcr.io/tuist/macos-tahoe-xcode:26-4-1"
}

variable "output_image" {
  type        = string
  description = "Output image name (e.g. tuist-xcresult-processor)."
  default     = "tuist-xcresult-processor"
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
  ssh_timeout = "15m"
  headless    = true
}

build {
  sources = ["source.tart-cli.xcresult_processor"]

  provisioner "file" {
    source      = "${path.root}/../certificate-trust/pem-store.sh"
    destination = "/tmp/tuist-pem-store.sh"
  }
  provisioner "file" {
    source      = "${path.root}/../certificate-trust/policy.json"
    destination = "/tmp/policy.json"
  }
  provisioner "file" {
    source      = "${path.root}/../certificate-trust/controls/aaa-cross-signed-intermediate.pem"
    destination = "/tmp/tuist-negative-intermediate.pem"
  }
  provisioner "file" {
    source      = "${path.root}/../certificate-trust/controls/issuer-roots.pem"
    destination = "/tmp/tuist-issuer-roots.pem"
  }
  provisioner "file" {
    source      = "${path.root}/../certificate-trust/controls/positive-isrg-root-x1.pem"
    destination = "/tmp/tuist-positive-root.pem"
  }

  # Native clients use deny settings. OTP ignores those settings, so the
  # xcresult release explicitly loads and checks this filtered PEM at boot.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain > /tmp/tuist-system-roots.pem",
      "bash /tmp/tuist-pem-store.sh extract-blocked /tmp/tuist-system-roots.pem /tmp/tuist-blocked-cas",
      "openssl verify -CAfile /tmp/tuist-issuer-roots.pem /tmp/tuist-negative-intermediate.pem",
      "if security verify-cert -c /tmp/tuist-negative-intermediate.pem -p basic -R offline >/dev/null 2>&1; then echo 'Native negative-chain baseline: trusted before containment'; else echo 'Native negative-chain baseline: already rejected; no differential containment claim'; fi",
      "echo 'admin' | sudo -S true",
      "right=$(mktemp)",
      "sudo security authorizationdb read com.apple.trust-settings.admin > \"$right\"",
      "trap 'sudo security authorizationdb write com.apple.trust-settings.admin < \"$right\" || exit 1; rm -f \"$right\"' EXIT",
      "sudo security authorizationdb write com.apple.trust-settings.admin allow",
      "for cert in /tmp/tuist-blocked-cas/*.pem; do [ -e \"$cert\" ] || continue; sudo security add-trusted-cert -d -r deny -k /Library/Keychains/System.keychain \"$cert\"; if security verify-cert -c \"$cert\" -p basic >/dev/null 2>&1; then echo 'Native verifier accepted a denied root' >&2; exit 1; fi; done",
      "sudo security authorizationdb write com.apple.trust-settings.admin < \"$right\"; rm -f \"$right\"; trap - EXIT",
      "if security verify-cert -c /tmp/tuist-negative-intermediate.pem -p basic -R offline >/dev/null 2>&1; then echo 'Native verifier accepted a compromised intermediate chain' >&2; exit 1; fi",
      "security verify-cert -c /tmp/tuist-positive-root.pem -p basic -R offline",
      "bash /tmp/tuist-pem-store.sh filter /etc/ssl/cert.pem /tmp/tuist-cacerts.pem",
      "bash /tmp/tuist-pem-store.sh check /tmp/tuist-cacerts.pem",
      "echo 'admin' | sudo -S install -m 0644 /tmp/tuist-cacerts.pem /etc/ssl/cert.pem",
      "rm /tmp/tuist-cacerts.pem",
      "/opt/homebrew/bin/brew update",
      "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 /opt/homebrew/bin/brew upgrade ca-certificates",
      "bash /tmp/tuist-pem-store.sh filter /opt/homebrew/etc/ca-certificates/cert.pem /tmp/tuist-homebrew-roots.pem",
      "sudo install -m 0644 /tmp/tuist-homebrew-roots.pem /opt/homebrew/etc/ca-certificates/cert.pem",
      "bash /tmp/tuist-pem-store.sh check /etc/ssl/cert.pem /opt/homebrew/etc/ca-certificates/cert.pem",
      "rm -f /tmp/tuist-negative-intermediate.pem /tmp/tuist-issuer-roots.pem /tmp/tuist-positive-root.pem /tmp/tuist-system-roots.pem /tmp/tuist-homebrew-roots.pem",
      "rm -rf /tmp/tuist-blocked-cas"
    ]
  }

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

  # Sanity check: xcresulttool has to be reachable before the
  # processor ever calls it. The macos-tahoe-xcode base installs
  # Xcode + xcode-select's it; a regression there would silently
  # break ingestion at runtime. Fail loudly here so the image
  # build catches it.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "/usr/bin/xcrun xcresulttool version || (echo 'xcresulttool not reachable — macos-tahoe-xcode base image regression' >&2 && exit 1)"
    ]
  }

  # launchd sets the unit's WorkingDirectory before the boot chain runs, so
  # the directory fetch-release.sh fills has to exist in the image.
  provisioner "shell" {
    inline = [
      "mkdir -p /opt/tuist/release"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/fetch-release.sh"
    destination = "/tmp/fetch-release.sh"
  }

  provisioner "shell" {
    inline = [
      "echo 'admin' | sudo -S install -m 0755 /tmp/fetch-release.sh /opt/tuist/fetch-release.sh",
      "rm -f /tmp/fetch-release.sh"
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
