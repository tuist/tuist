# Evidence: isolation tooling on the test Mac

## Tart

Installed manually from the release archive:

```text
version: 2.31.0
artifact: tart.tar.gz
sha256: 28d9ef50a2f007d5b22ee70891f3578ec6f290593ea113373e31400a933efe30
```

Basic CLI validation succeeded:

```text
tart --version => 2.31.0
tart list => no VMs present yet
```

Two base images were cloned successfully:

```text
ghcr.io/cirruslabs/macos-tahoe-base:latest -> tuist-tahoe-base
ghcr.io/cirruslabs/macos-sequoia-base:latest -> tuist-sequoia-base
```

Resource tuning used for this host:

```text
cpu=2
memory=4096 MB
```

Useful capability discovered from `tart run --help`:

- `--no-graphics`
- `--net-softnet`
- `--net-softnet-allow`
- `--net-softnet-block`
- `--dir` for virtio-fs directory shares
- `--disk` for remote/local disk attachments

Interpretation:

- Tart is viable as the likely VM boundary for future per-run isolation.
- Softnet is especially relevant because it provides stronger network isolation for VM workloads.

### Live boot result on this host

Attempting to boot both Tahoe and Sequoia guests over SSH failed with the same error:

```text
Error Domain=VZErrorDomain Code=-9
"The virtual machine encountered a security error."
...
Failed to get current host key.
Failed to create new HostKey.
```

Additional host observations:

```text
launchctl print gui/501 => no active GUI session visible
login.keychain-db exists for m1 but is locked in this session
security show-keychain-info ... => User interaction is not allowed
security unlock-keychain -p '' ... => passphrase not correct
```

Interpretation:

- Tart's VM boundary does work on this host, but only after a real GUI login session for `m1`.
- The documented keychain-only workaround was not enough by itself.
- Host session preparation is therefore a real fleet bootstrap concern.

### Guest networking result

Default NAT mode:

- guest received `192.168.64.2`
- public cache URL worked
- private cache IP `172.16.16.4` did not work

Bridged `vlan0` mode:

- guest booted
- DHCP only produced a link-local `169.254.x.x` address
- after manually assigning `172.16.16.10/22`, private cache access worked directly
- after setting DNS servers manually, public internet still worked in the same guest

Interpretation:

- VM execution is viable
- direct private guest access to the cache VPC is viable if the guest is explicitly configured with a static `172.16.16.x` address on the bridged VLAN
- DHCP on the bridged VLAN is not sufficient by itself
- this implies VM bootstrapping needs per-VM private IP allocation logic

## nono

Installed manually from the release archive:

```text
version: 0.16.0
artifact: nono-v0.16.0-aarch64-apple-darwin.tar.gz
sha256: b8cc471c724659f1a047400e96950dd43167219d344bd8ceb595386d8dac008f
```

Positive smoke test:

```text
nono run --allow ~/nono-test -- bash -lc 'pwd; touch ~/nono-test/ok; ls ~/nono-test'
=> success
```

Negative smoke test:

```text
nono run --allow ~/nono-test -- bash -lc 'touch ~/should-be-blocked'
=> Operation not permitted
```

Interesting observation:

```text
nono run --read ~/nono-test -- bash -lc 'cat /etc/hosts'
=> allowed
```

Interpretation:

- nono is useful as a syscall/path-level hardening layer.
- It is not a full VM or container boundary.
- It may be valuable inside a guest or around specific runner-side helper processes, but it is not a complete multi-tenant isolation answer by itself.
