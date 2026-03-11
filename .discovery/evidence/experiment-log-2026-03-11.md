# Experiment log - 2026-03-11

This file records the concrete steps taken during discovery and what came back.

## 1. Basic SSH and host identity

Command:

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new m1@51.159.120.232 "hostname && sw_vers && uname -a"
```

Result:

```text
16356b55-76c6-4b86-b792-02a11f334a5c
ProductName: macOS
ProductVersion: 26.0
BuildVersion: 25A354
Darwin ... arm64
```

## 2. Toolchain and runner state

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "printf 'HOSTNAME '; hostname; printf 'USER '; whoami; printf 'ID '; id; printf 'SUDO '; sudo -n true >/dev/null 2>&1 && echo yes || echo no; printf 'SW_VERS\n'; sw_vers; printf 'XCODE_SELECT '; xcode-select -p 2>/dev/null || true; printf 'XCODEBUILD\n'; xcodebuild -version 2>/dev/null || true; printf 'NIX '; nix --version 2>/dev/null || echo missing; printf 'DARWIN_REBUILD '; darwin-rebuild --version 2>/dev/null || echo missing; printf 'BREW '; brew --version 2>/dev/null | sed -n '1p' || echo missing; printf 'GH '; gh --version 2>/dev/null | sed -n '1p' || echo missing; printf 'RUNNER_FILES\n'; ls -1 ~/actions-runner 2>/dev/null || echo missing; printf 'LAUNCHD_RUNNER\n'; launchctl list | grep -i actions.runner || echo none"
```

Key result:

```text
SUDO no
Xcode 26.0
NIX missing
DARWIN_REBUILD missing
RUNNER_FILES missing
LAUNCHD_RUNNER none
```

## 3. Hardware and virtualization support

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "printf 'CPU '; sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model; printf '\nCORES '; sysctl -n hw.physicalcpu; printf '\nLOGICAL '; sysctl -n hw.logicalcpu; printf '\nMEM_BYTES '; sysctl -n hw.memsize; printf '\nDISK\n'; df -h / /System/Volumes/Data; printf 'VIRT\n'; sysctl -a 2>/dev/null | grep -E 'kern.hv_support' | sed -n '1,20p'"
```

Key result:

```text
CPU Apple M1
CORES 8
LOGICAL 8
MEM_BYTES 8589934592
kern.hv_support: 1
```

## 4. Cache-node addressing and health

Command:

```bash
ssh -o BatchMode=yes cschmatzler@51.159.83.73 "hostname; ip -brief addr; ip route; curl -ksS --resolve 'tuist-01-test-cache.par.runners.tuist.dev:443:127.0.0.1' --max-time 5 https://tuist-01-test-cache.par.runners.tuist.dev/up -D -"
```

Key result:

```text
tuist-01-test-cache
ens6 UP 172.16.16.4/22
HTTP/2 200
UP! Version: ...
```

## 5. Private-network test from the Mac

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "printf 'ROUTE\n'; route -n get 172.16.16.4 2>/dev/null || true; printf 'PING\n'; ping -c 2 -W 1000 172.16.16.4; printf 'CACHE_UP\n'; curl -sS -D - --max-time 5 http://172.16.16.4/up -o /tmp/cache-up.out && cat /tmp/cache-up.out"
```

Key result:

```text
route to: 172.16.16.4
destination: default
gateway: 51.159.120.1
interface: en0

PING ... 100.0% packet loss
curl: (28) Connection timed out after 5009 milliseconds
```

## 6. Public cache access from the Mac

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "curl -ksS --max-time 5 https://tuist-01-test-cache.par.runners.tuist.dev/up -D -"
```

Result:

```text
HTTP/2 200
UP! Version: ...
```

## 7. VLAN state and requirements

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "printf 'VLANS\n'; networksetup -listVLANs 2>/dev/null || true; printf '\nSUDO_VLAN_TEST\n'; sudo -n networksetup -createVLAN testvlan en0 123 2>&1 || true; printf '\nMANPAGE_HINT\n'; networksetup -help 2>&1 | grep -n 'createVLAN\|listVLANs\|deleteVLAN' | sed -n '1,20p'"
```

Key result:

```text
There are no VLANs currently configured on this system.
sudo: a password is required
Usage: networksetup -createVLAN <VLAN name> <device name> <tag>
```

## 8. Xcode and simulator state

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "printf 'FIRST_LAUNCH_EXIT '; xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; echo $?; printf 'XCODEBUILD_VERSION\n'; xcodebuild -version; printf 'SIMCTL_RUNTIMES_JSON\n'; xcrun simctl list runtimes --json 2>&1 | sed -n '1,120p'"
```

Key result:

```text
FIRST_LAUNCH_EXIT 0
Xcode 26.0
SIMCTL_RUNTIMES_JSON
{ "runtimes" : [ ] }
```

Interpretation:

- Xcode is present, but simulator runtimes are not currently available through `simctl`.

## 9. Inspect Determinate Nix Installer on the host

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "rm -f /tmp/nix-installer && curl -fsSL -o /tmp/nix-installer https://github.com/DeterminateSystems/nix-installer/releases/download/v3.17.0/nix-installer-aarch64-darwin && chmod +x /tmp/nix-installer && /tmp/nix-installer --help | sed -n '1,80p' && printf '\nPLAN_HELP\n' && /tmp/nix-installer plan --help | sed -n '1,80p' && printf '\nINSTALL_HELP\n' && /tmp/nix-installer install macos --help | sed -n '1,120p'"
```

Key result:

```text
Commands: install, repair, uninstall, self-test, plan
plan macos
install macos
```

## 10. Try to generate an install plan

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "/tmp/nix-installer plan --out-file /tmp/nix-plan.json macos >/dev/null && ..."
```

Result:

```text
`nix-installer` needs to run as `root`, attempting to escalate now via `sudo`...
sudo: a terminal is required to read the password
sudo: a password is required
```

Interpretation:

- even installer planning requires root on this host
- no further Nix bootstrap experiment can proceed without admin credentials

## 11. Inspect official GitHub runner bundle

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "rm -rf ~/tmp-actions-runner && mkdir -p ~/tmp-actions-runner && cd ~/tmp-actions-runner && curl -fsSLO https://github.com/actions/runner/releases/download/v2.332.0/actions-runner-osx-arm64-2.332.0.tar.gz && shasum -a 256 actions-runner-osx-arm64-2.332.0.tar.gz | sed -n '1p' && tar xzf actions-runner-osx-arm64-2.332.0.tar.gz && ./config.sh --help | sed -n '1,120p'"
```

Key result:

```text
d53bedb30619a64e751bb9f729cc9e9b35eb1df5361651d54daae00db33f2e73  actions-runner-osx-arm64-2.332.0.tar.gz
default labels: self-hosted,OSX,Arm64
supports: --runnergroup, --labels, --replace, --disableupdate, --ephemeral
```

## 12. Inspect Xcode management tooling (`xcodes`)

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "cd ~/tmp-xcodes/xcodes/1.6.2 && ./bin/xcodes installed 2>&1 | sed -n '1,80p' && printf '\nXCODES_LIST_26\n' && ./bin/xcodes list 2>&1 | grep '26\.' | sed -n '1,60p' && printf '\nXCODES_RUNTIMES\n' && ./bin/xcodes runtimes 2>&1 | sed -n '1,80p' && printf '\nXCODES_INSTALL_HELP\n' && ./bin/xcodes install --help | sed -n '1,120p'"
```

Key result:

```text
26.0 (17A321) (Selected) /Applications/Xcode.app
26.2 (17C52)
iOS 26.2
install supports: --directory, --experimental-unxip, --no-superuser, --use-fastlane-auth
```

Interpretation:

- `xcodes` can see the required `26.2`
- `xcodes` can see `iOS 26.2` runtimes
- there is a plausible user-space Xcode strategy via `--directory` and `--no-superuser`

## 13. Host key and secret tooling check

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "printf 'HOSTKEY_PUB\n'; cat /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null || echo unavailable; printf '\nOP_CLI\n'; op --version 2>/dev/null || echo missing"
```

Key result:

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAPv7cQzsutmJ5EEjB1Pm0QfV0o3n8Gxq2oUNBA1jrOr
op missing
```

Interpretation:

- SSH host-key-based secret schemes are viable
- 1Password CLI is not currently installed

## 14. Discover VLAN tag from live traffic

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "sudo tcpdump -G 5 -W 1 -U -nn -e -i en0 vlan -w /tmp/vlan-capture.pcap >/dev/null 2>&1; sudo tcpdump -nn -e -r /tmp/vlan-capture.pcap"
```

Traffic stimulation from the cache node:

```bash
ssh -o BatchMode=yes cschmatzler@51.159.83.73 "sudo -n arping -c 20 -I ens6 172.16.16.3"
```

Key result:

```text
ethertype 802.1Q ... vlan 1597 ... ARP who-has 172.16.16.3 tell 172.16.16.4
```

Interpretation:

- the live Private Network VLAN tag for this setup is `1597`

## 15. Create the macOS VLAN interface

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "sudo networksetup -createVLAN pn en0 1597"
```

Immediate verification:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "networksetup -listVLANs; ipconfig getifaddr vlan0; ipconfig getpacket vlan0"
```

Key result:

```text
VLAN User Defined Name: pn
Parent Device: en0
Device: vlan0
Tag: 1597

ipconfig getifaddr vlan0
172.16.16.3
```

Interpretation:

- the local macOS VLAN setup is now proven
- DHCP on the Private Network works from macOS once the VLAN exists

## 16. Discover the cache-node routing bug

Command:

```bash
ssh -o BatchMode=yes cschmatzler@51.159.83.73 "ip addr show dev ens6; ip route get 172.16.16.3; ip route show table main"
```

Key result:

```text
inet 172.16.16.4/22 scope global dynamic noprefixroute ens6
ip route get 172.16.16.3
172.16.16.3 via 62.210.0.1 dev ens2 src 51.159.83.73
```

Interpretation:

- the cache node's private interface had the right IP but no connected route
- replies to the Mac went out the public interface

## 17. Temporary route fix on the cache node

Command:

```bash
ssh -o BatchMode=yes cschmatzler@51.159.83.73 "sudo ip route add 172.16.16.0/22 dev ens6 src 172.16.16.4 && ip route get 172.16.16.3"
```

Key result:

```text
172.16.16.3 dev ens6 src 172.16.16.4
```

## 18. End-to-end private connectivity after both fixes

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "ping -c 3 172.16.16.4; curl -ksS --max-time 5 https://172.16.16.4/up -D -"
```

Also from the cache node:

```bash
ssh -o BatchMode=yes cschmatzler@51.159.83.73 "ping -c 3 172.16.16.3"
```

Key result:

```text
Mac -> cache ping: success
Mac -> https://172.16.16.4/up: HTTP/2 200
Cache -> Mac ping: success
```

Interpretation:

- the VLAN setup on the Mac is correct
- the remaining connectivity issue was the cache node route

## 19. Install Nix on the Mac

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "curl -fsSL -o /tmp/nix-installer.sh https://github.com/DeterminateSystems/nix-installer/releases/download/v3.17.0/nix-installer.sh && chmod +x /tmp/nix-installer.sh && sudo /tmp/nix-installer.sh install macos --no-confirm --no-modify-profile"
```

Key result:

```text
Nix was installed successfully
```

Follow-up verification:

```text
nix (Determinate Nix 3.17.0) 2.33.3
```

And the installer created a dedicated APFS Nix Store volume mounted at `/nix`.

## 20. Validate `darwin-rebuild` availability on the Mac

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix run nix-darwin/master#darwin-rebuild -- --help"
```

Key result:

```text
darwin-rebuild [--help] {edit | switch | activate | build | check | changelog} ...
```

## 21. Create and evaluate the first `/runners` flake

Local evaluation commands:

```bash
nix flake show path:/home/cschmatzler/Projects/Work/tuist/runners
nix eval --raw path:/home/cschmatzler/Projects/Work/tuist/runners#darwinConfigurations."scaleway-m1-01".config.system.build.toplevel.drvPath
```

Key result:

```text
darwinConfigurations.scaleway-m1-01
/nix/store/...-darwin-system-26.05....drv
```

Remote evaluation on the Mac also succeeded after copying the `/runners` directory to `~/tuist-runners`.

## 22. First remote `darwin-rebuild -- build`

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && sudo nix run nix-darwin/master#darwin-rebuild -- build --flake path:/Users/m1/tuist-runners#scaleway-m1-01"
```

Outcome:

```text
FAILED
error: Cannot build ... nodejs-slim-20.20.1.drv
Reason: builder failed with exit code 139
Segmentation fault: 11
```

Interpretation:

- the flake is structurally valid
- the host can evaluate it
- the current blocker is package build reliability for `github-runner` and its Node dependency on this host

## 23. Deploy the cache-node route fix through NixOS

Command:

```bash
nixos-rebuild switch --flake .#tuist-01-test-cache --target-host cschmatzler@51.159.83.73 --build-host cschmatzler@51.159.83.73 --use-remote-sudo
```

Key result:

```text
the following new units were started: network-addresses-ens6.service
Done. The new configuration is /nix/store/...-nixos-system-tuist-01-test-cache-...
```

Post-deploy verification:

```text
ip route get 172.16.16.3
172.16.16.3 dev ens6 src 172.16.16.4
```

And from the Mac:

```text
ping 172.16.16.4: success
curl -k https://172.16.16.4/up: HTTP/2 200
```

## 24. Replace the source-built runner package with a binary wrapper package

Problem observed earlier:

```text
nodejs-slim-20.20.1 segfaulted while building the nixpkgs github-runner package
```

New approach implemented in `/runners/pkgs/github-runner-binary.nix`:

- fetch the official GitHub runner tarball
- keep the extracted tree as a template in the Nix store
- copy it into `RUNNER_ROOT` when `config.sh` or `Runner.Listener` is invoked
- avoid local Node.js compilation entirely

## 25. Rebuild the `/runners` flake with the binary runner package

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && sudo nix run nix-darwin/master#darwin-rebuild -- build --flake path:/Users/m1/tuist-runners#scaleway-m1-01"
```

Observed result:

```text
the `github-runner-binary-2.332.0` derivation built successfully
the build no longer hit the local Node.js segfault path
```

## 26. Validate the wrapper package directly on the Mac

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 'out=$(ls -dt /nix/store/*-github-runner-binary-2.332.0 | head -1); export RUNNER_ROOT=$HOME/runner-wrapper-test; "$out/bin/config.sh" --help; "$out/bin/Runner.Listener" --version'
```

Key result:

```text
config.sh help output printed successfully
Runner.Listener --version => 2.332.0
```

And the wrapper copied a mutable runner tree into `~/runner-wrapper-test`.

## 27. Build the runner system directly with `nix build`

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 'zsh -lc ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && cd ~/tuist-runners && nix build .#darwinConfigurations.\"scaleway-m1-01\".config.system.build.toplevel --print-out-paths --no-link"'
```

Key result:

```text
/nix/store/vlp61d7fgqzapcircj9plh0r9aj018ry-darwin-system-26.05.da529ac
```

Interpretation:

- the `/runners` flake now builds end-to-end on the live Mac
- the remaining missing piece before activation is real secret material for runner registration and Xcode bootstrap

## 28. First safe `darwin-rebuild switch`

Before switching, the host config was adjusted so that:

- `nix.enable = false` to avoid fighting the existing Determinate Nix install
- the GitHub runner service stays disabled until the server-backed control plane is ready
- Homebrew bootstrap does not attempt to manage the `xcodes` tap during activation

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 'zsh -lc ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && cd ~/tuist-runners && sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake .#scaleway-m1-01"'
```

Final result:

```text
Homebrew bundle...
Using aria2
`brew bundle` complete! 1 Brewfile dependency now installed.
```

Interpretation:

- the first safe host activation succeeded
- the Mac is now running the bootstrap config from `/runners`

## 29. Install `xcodes` CLI separately from the host switch

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "curl -fsSL -o /tmp/xcodes.tgz https://github.com/XcodesOrg/xcodes/releases/download/1.6.2/xcodes-1.6.2.macos.arm64.tar.gz && rm -rf /tmp/xcodes-install && mkdir -p /tmp/xcodes-install && tar -xzf /tmp/xcodes.tgz -C /tmp/xcodes-install && sudo cp /tmp/xcodes-install/xcodes/1.6.2/bin/xcodes /usr/local/bin/xcodes && sudo chmod 0755 /usr/local/bin/xcodes && /usr/local/bin/xcodes version"
```

Key result:

```text
1.6.2
```

Also verified:

```text
xcodes list | grep 26.2
26.2 (17C52)
```

## 30. Attempt Xcode 26.2 install

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "mkdir -p ~/Applications && /usr/local/bin/xcodes install 26.2 --directory ~/Applications --select --no-superuser --empty-trash --experimental-unxip"
```

Key result:

```text
Apple ID: Missing username or a password. Please try again.
```

Interpretation:

- the installation path is ready
- the remaining blocker for `Xcode 26.2` is Apple authentication material

## 31. Product-architecture correction

The initial secret model treated the runner token like a host secret.

That is now corrected:

- the runner token path is runtime-only (`/var/run/tuist/github-runner.token`)
- static SOPS-managed runner tokens are no longer part of the design
- the multi-tenant path now assumes server-issued dynamic registration material

## 32. Enable host-side secrets management for `xcodes`

What changed:

- added a host-specific encrypted SOPS file under `/runners/secrets/`
- enabled `tuist.runner.secrets` for `scaleway-m1-01`
- switched the host successfully with `sops-nix`

Verification on the host:

```text
/etc/tuist/xcodes.env -> /run/secrets/xcodes-env
```

Interpretation:

- Apple/Xcode bootstrap material is now delivered through secrets management only

## 33. Retry Xcode 26.2 install using managed secret

Command:

```bash
ssh -o BatchMode=yes m1@51.159.120.232 "sudo bash -lc 'set -a; source /etc/tuist/xcodes.env; set +a; /usr/local/bin/xcodes install 26.2 --select --empty-trash --experimental-unxip'"
```

Key result:

```text
Invalid username and password combination
```

And `xcodes` then failed to decode the response because the Apple auth flow returned HTML instead of the expected JSON payload.

Interpretation:

- the secrets-management path is correct
- the current Apple credential form is not accepted by `xcodes`
- the next likely fix is `FASTLANE_SESSION`, or a different Apple auth method compatible with `xcodes`

## 34. Clarify Apple credential type

Follow-up finding:

```text
the provided Apple credential is an app-specific password
```

Interpretation:

- this explains the failed `xcodes` login
- `xcodes` is using an Apple web sign-in flow, not an app-specific-password flow
- app-specific passwords are therefore not sufficient for the Xcode download path on this host

## 35. Retry with normal Apple ID password via managed secret

What changed:

- the host-specific SOPS file was updated to carry the normal Apple ID password in `xcodes-env`
- the secret was redeployed to the Mac through `sops-nix`

Verification:

```text
/etc/tuist/xcodes.env -> /run/secrets/xcodes-env
```

## 36. Retry Xcode install with the normal Apple ID password

Command form used:

```bash
sudo -H -u m1 env XCODES_USERNAME=... XCODES_PASSWORD=... /usr/local/bin/xcodes install 26.2 --select --empty-trash --experimental-unxip
```

Result:

```text
DecodingError.keyNotFound(... "salt" ...)
```

Retrying with a forced TTY produced the same result.

Interpretation:

- the failure is no longer explained by noninteractive SSH alone
- the credential is being consumed by `xcodes`, but Apple returns an auth response shape that `xcodes` does not handle in this case

## 37. Upstream `xcodes` research

Relevant upstream evidence:

- `xcodes` README still documents `XCODES_USERNAME` and `XCODES_PASSWORD` as supported input
- open upstream issue `XcodesOrg/xcodes#395` explains one concrete reason for the exact auth family of failures:

```text
If your password is very old (pre SRP), Apple may not have the SRP salt/verifier needed by the newer login flow.
Changing the Apple ID password refreshes those values.
```

There is also an open upstream federated-authentication effort, but the current failure pattern matches the SRP/salt issue more closely than the documented federated 403 flow.

## 38. Manual interactive Xcode install succeeded

Observed manual host session outcome:

```text
xcodes install 26.2
Two-factor authentication is enabled for this account.
...
Xcode 26.2.0 has been installed to /Applications/Xcode-26.2.0.app
```

Important notes:

- interactive installation can succeed on the host
- the automation gap is specifically around unattended auth and finalization, not the host's general ability to install Xcode
- the installed path shape is `Xcode-26.2.0.app`, not `Xcode_26.2.app`

## 39. Install Tart and nono manually on the test Mac

Tart install command shape:

```bash
curl -fsSL -o /tmp/tart.tar.gz https://github.com/cirruslabs/tart/releases/download/2.31.0/tart.tar.gz
tar -xzf /tmp/tart.tar.gz -C /tmp/tart-install
sudo cp -R /tmp/tart-install/tart.app /Applications/tart.app
sudo ln -sf /Applications/tart.app/Contents/MacOS/tart /usr/local/bin/tart
```

Key result:

```text
tart --version => 2.31.0
```

nono install command shape:

```bash
curl -fsSL -o /tmp/nono.tar.gz https://github.com/always-further/nono/releases/download/v0.16.0/nono-v0.16.0-aarch64-apple-darwin.tar.gz
tar -xzf /tmp/nono.tar.gz -C /tmp/nono-install
sudo cp /tmp/nono-install/nono /usr/local/bin/nono
sudo chmod 0755 /usr/local/bin/nono
```

Key result:

```text
nono --version => 0.16.0
```

## 40. nono smoke tests on macOS

Positive test:

```text
nono run --allow ~/nono-test -- bash -lc 'touch ~/nono-test/ok'
=> success
```

Negative test:

```text
nono run --allow ~/nono-test -- bash -lc 'touch ~/should-be-blocked'
=> Operation not permitted
```

Interpretation:

- nono does provide useful path-level enforcement on macOS
- but it is not equivalent to VM-backed isolation

## 41. Align host config with runtime Xcode resolution

What changed:

- removed hardcoded `DEVELOPER_DIR` from the host-level runner config
- kept Xcode path resolution in the workflow-side `select-xcode` action instead

Result:

```text
darwin-rebuild switch succeeded again on the test Mac
```

Interpretation:

- host config is now cleaner and less coupled to one exact on-disk Xcode path

## 42. Clone Tart macOS base images

Commands:

```bash
/Applications/tart.app/Contents/MacOS/tart clone ghcr.io/cirruslabs/macos-tahoe-base:latest tuist-tahoe-base
/Applications/tart.app/Contents/MacOS/tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest tuist-sequoia-base
```

Result:

```text
Tahoe base clone succeeded
Sequoia base clone succeeded
```

Resource adjustment used for both VMs:

```bash
/Applications/tart.app/Contents/MacOS/tart set <vm> --cpu 2 --memory 4096
```

## 43. Attempt headless Tart boot

Command shape:

```bash
nohup /Applications/tart.app/Contents/MacOS/tart run --no-graphics <vm> >/tmp/<vm>.log 2>&1 &
```

Observed result for both Tahoe and Sequoia guests:

```text
Error Domain=VZErrorDomain Code=-9
The virtual machine encountered a security error.
Failed to get current host key.
Failed to create new HostKey.
```

## 44. Inspect keychain/headless prerequisites

Commands:

```bash
launchctl print gui/501
security show-keychain-info ~/Library/Keychains/login.keychain-db
security unlock-keychain -p '' ~/Library/Keychains/login.keychain-db
```

Key result:

```text
no active GUI session visible
login.keychain-db exists
show-keychain-info => User interaction is not allowed
unlock-keychain with empty password => passphrase not correct
```

Interpretation:

- the likely blocker is headless keychain/session state, not image download or Tart installation
- this matches Tart's FAQ guidance for macOS 15+ headless hosts

## 45. Install and smoke-test nono on macOS

Additional negative test:

```text
nono run --allow ~/nono-test -- bash -lc 'touch ~/should-be-blocked'
=> Operation not permitted
```

Interpretation:

- nono is a useful defense-in-depth layer
- it does not replace a VM boundary for multi-tenant isolation

## 46. Attempt Tart headless-keychain workaround

Goal:

- satisfy Tart's documented headless prerequisite on macOS 15+
- retry VM boot without changing the broader host bootstrap model

What was tried:

1. create alternate unlocked keychains for `m1`
2. set them as default/login keychains
3. retry Sequoia VM boot
4. as a stronger reversible test, temporarily back up `login.keychain-db`, create a fresh `login.keychain`, set it as the login/default keychain, and retry boot

Observed result:

```text
Tart still fails with:
Failed to get current host key
Failed to create new HostKey
```

Additional host facts:

```text
autoLoginUser: unset
who: no GUI user session shown
launchctl print gui/501 => domain not available
```

Interpretation:

- the documented keychain-only workaround was not enough on this host
- the remaining missing ingredient is likely a real GUI login session and/or the true unlocked account login keychain
- this looks like a host session-state problem, not a Tart image problem

Cleanup:

- the original `login.keychain-db` was restored
- temporary keychain files and search-list changes were removed

## 47. Consequence for VM networking test

Because no Tart guest successfully booted, VM-to-cache networking could not be validated yet.

Current status:

- host-to-cache private networking works
- guest boot is still blocked on headless host state
- therefore guest-to-cache networking remains untested

## 48. GUI login unblocked Tart boot

After logging into the Mac via the GUI as `m1`:

```text
who => m1 console
launchctl print gui/501 => Aqua session present
```

Retry result:

```text
/Applications/tart.app/Contents/MacOS/tart run --no-graphics tuist-sequoia-base
=> VM started successfully
```

And:

```text
tart ip tuist-sequoia-base => 192.168.64.2
tart exec tuist-sequoia-base uname -a => success
```

Interpretation:

- the GUI login session was the missing ingredient for Tart on this host
- Tart VM boot is now validated, but only after an interactive GUI login

## 49. Test guest networking with default NAT

Inside the guest:

```text
default gateway => 192.168.64.1
```

Connectivity results:

```text
ping 172.16.16.4 => timeout
curl https://172.16.16.4/up => timeout
curl https://tuist-01-test-cache.par.runners.tuist.dev/up => HTTP/2 200
```

Interpretation:

- default Tart NAT gives outbound internet access
- but the guest cannot reach the cache node over the private `172.16.16.0/22` path

## 50. Test guest networking with bridged `vlan0`

Command shape:

```bash
/Applications/tart.app/Contents/MacOS/tart run --no-graphics --net-bridged=vlan0 tuist-sequoia-base
```

Boot result:

```text
VM started successfully
```

Guest network result:

```text
en0 inet 169.254.129.228/16
no default route to 172.16.16.4
ping 172.16.16.4 => no route / timeout
```

Cache-side observation:

```text
no ARP response seen for a guessed 172.16.16.x VM address
```

Interpretation:

- bridging directly to the Scaleway VLAN does not give the guest a usable `172.16.16.x` lease on this host
- the guest falls back to link-local addressing instead

## 51. Result of VM-to-cache networking probe

Current state:

- VM boot: yes, after GUI login
- VM to public cache URL: yes
- VM to private cache IP over default NAT: no
- VM to private cache IP over bridged `vlan0`: no

Practical conclusion:

- Tart VM execution is now viable on this host
- but private guest access to the cache node remains unsolved
- a separate host-level routing/proxy design or a different VM networking mode will be required if guest workloads must use the cache over VPC

## 52. Prove direct private guest-to-cache with a static bridged IP

Setup:

```bash
/Applications/tart.app/Contents/MacOS/tart run --no-graphics --net-bridged=vlan0 tuist-sequoia-base
```

Inside the guest:

```bash
sudo /sbin/ifconfig en0 inet 172.16.16.10 netmask 255.255.252.0 up
```

Key result from host `tcpdump` on `vlan0`:

```text
ARP who-has 172.16.16.4 tell 172.16.16.10
ARP reply 172.16.16.4 is-at ...
ICMP echo request/reply 172.16.16.10 <-> 172.16.16.4
HTTPS traffic 172.16.16.10:49152 -> 172.16.16.4:443
```

Guest result:

```text
ping 172.16.16.4 => success
curl https://172.16.16.4/up => HTTP/2 200
```

Cache-side ARP table also learned the VM MAC:

```text
172.16.16.10 lladdr 06:e8:a3:b0:23:b4 STALE
```

Interpretation:

- direct private VM-to-cache networking does work on this host
- the blocker was not VLAN bridging itself, but lack of DHCP on the bridged guest

## 53. Public internet in the same bridged guest

Additional guest setup:

```bash
/usr/sbin/networksetup -setdnsservers Ethernet 1.1.1.1 8.8.8.8
```

Observed routing state in the guest during the successful run:

```text
default gateway => 192.168.64.1
private subnet route => 172.16.16.0/22 via en0
```

Validation:

```text
ping 8.8.8.8 => success
curl -4 -I https://github.com => HTTP/2 200
```

Interpretation:

- in the successful bridged run, the guest retained public egress while also gaining direct private cache access
- manual DNS configuration was required to make name resolution reliable

## 54. Refined networking conclusion

The previous conclusion that VM-to-cache private networking was unsolved was too pessimistic.

More accurate conclusion:

- default Tart NAT: public internet yes, private cache no
- bridged `vlan0` with DHCP only: private cache no
- bridged `vlan0` with manual static `172.16.16.x` + DNS setup: private cache yes, public internet yes in the validated run

This makes direct private guest-to-cache access a viable candidate, but only if VM bootstrapping configures:

- a unique static private IP per VM
- subnet route on `en0`
- DNS servers

## 55. Validate host-relay implementation on Tart NAT

This became the simpler winning model.

Host side:

```bash
nix shell nixpkgs#socat --command sudo socat TCP-LISTEN:443,bind=192.168.64.1,reuseaddr,fork TCP:172.16.16.4:443
```

Guest side:

```bash
echo "192.168.64.1 tuist-01-test-cache.par.runners.tuist.dev" | sudo tee -a /etc/hosts
curl -ksS https://tuist-01-test-cache.par.runners.tuist.dev/up -D -
```

Validated result on a fresh NAT guest:

```text
guest public internet => works
guest cache domain via host relay => HTTP/2 200
```

Interpretation:

- this is the simplest current implementation that preserves both public internet and private cache access
- the host carries the private-network responsibility; the guest stays on normal Tart NAT

## 56. Implement helper scripts in `/runners`

Added:

- `ensure-tart-cache-relay.nu`
- `bootstrap-tart-cache.nu`
- `run-tart-vm-with-private-cache.nu`
- `cleanup-tart-cache.nu`

Validated from the checked-in scripts on the Mac host:

```text
cache relay already listening on 192.168.64.1:443
guest IP allocated on Tart NAT
guest cache healthcheck over cache hostname => HTTP/2 200
cleanup script removed the guest hosts entry successfully
```

## 57. Convert the relay into a managed launchd service

Added Nix module:

- `runners/modules/tart-cache-relay.nix`

Host config change:

- `tuist.runner.tartCacheRelay.enable = true`

Validation after `darwin-rebuild switch`:

```text
launchd service created: io.tuist.tart-cache-relay
```

Important caveat discovered during validation:

```text
socat bind 192.168.64.1:443 => Can't assign requested address
```

Interpretation:

- the launchd service is correct
- but `192.168.64.1` only exists after Tart's `bridge100` comes up
- therefore the relay must be kickstarted after VM boot, not before

This sequencing was then moved into the checked-in helper flow.

## 58. Harden relay activation path

The managed launchd service remains the preferred mechanism.

However, because bind timing around `bridge100` can still be noisy, `ensure-tart-cache-relay.nu` was hardened to:

1. kickstart the managed launchd relay
2. check whether `192.168.64.1:443` is actually listening
3. start a one-shot fallback `socat` relay only if the listener is still absent

Interpretation:

- launchd remains the durable steady-state design
- the helper now makes the worker lifecycle resilient to relay bind timing races

## 59. Validate disposable assignment lifecycle scripts

Added worker-oriented scripts:

- `create-tart-assignment-vm.nu`
- `normalize-tart-guest-network.nu`
- `exec-tart-assignment.nu`
- `destroy-tart-assignment-vm.nu`

Validation flow on the test Mac:

1. clone `tuist-assignment-demo-001` from `tuist-sequoia-base`
2. start the clone
3. normalize guest network back to DHCP/default NAT
4. ensure host relay
5. bootstrap cache hostname inside guest
6. verify cache healthcheck from inside guest
7. destroy the clone

Observed result:

```text
guest cache healthcheck => HTTP/2 200
clone deleted successfully after cleanup
```

Important finding:

- base-image mutations from earlier experiments can leak into clones
- guest network normalization is therefore part of the worker lifecycle now

## 60. Add payload-driven worker scripts

Added:

- `runners/examples/assignment-payload.sample.json`
- `runners/scripts/stage-tart-assignment-registration.nu`
- `runners/scripts/run-tart-assignment-from-payload.nu`

Purpose:

- let a future `server/` assignment payload drive clone creation, cache bootstrap, and guest registration staging

## 61. Payload-driven validation result

Observed result on the test Mac:

- payload-driven flow reached:
  - clone creation
  - guest network normalization
  - managed relay activation
  - cache hostname injection
  - successful cache healthcheck from inside the clone
  - registration staging inside the guest

Interpretation:

- the server/worker payload contract is now concrete enough to implement
- the clone-stability problem was fixed by changing VM launch from a Nushell background job to a truly detached shell launch

## 62. Validate registration staging inside the disposable guest

After the detached-launch fix, the payload-driven flow produced these guest-side runtime artifacts:

```text
/var/run/tuist/github-runner-config.json
/var/run/tuist/github-runner.token
```

Observed config content:

```json
{
  "assignment_id": "demo-001",
  "registration_mode": "registration_token",
  "runner_name": "tuist-assignment-demo-001",
  "work_folder": "_work",
  "labels": [
    "self-hosted",
    "macos",
    "apple-silicon",
    "scaleway",
    "xcode-26-2"
  ]
}
```

Interpretation:

- assignment payload -> clone boot -> cache bootstrap -> registration staging now works end to end
- the next missing step is actual in-guest GitHub runner registration using the staged short-lived material
