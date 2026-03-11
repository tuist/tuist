# Tart cache access implementation

## Chosen implementation

Use the host as the private-network bridge for cache traffic while keeping Tart guests on the default NAT network.

## Why this is the best current implementation

- guest internet and DNS work naturally on Tart NAT
- cache traffic still goes privately from host to cache over the Scaleway VLAN
- no per-VM private IP lease management is required
- no guest route or DNS surgery is required beyond one hostname override
- this is simpler and more reproducible than the bridged-static-IP model

## Final traffic model

### Public traffic

- guest -> Tart NAT (`192.168.64.0/24`) -> public internet

### Cache traffic

- guest resolves cache hostname to `192.168.64.1`
- host listens on `192.168.64.1:443`
- host relays raw TCP to `172.16.16.4:443`
- host reaches cache over the private VLAN (`vlan0`)

This keeps TLS end-to-end with the cache service because the relay is TCP-level, not HTTP-level.

## Implementation pieces added

### Host requirements

- `nushell` installed
- `socat` installed
- `vlan0` already configured and working

### Scripts

- `runners/scripts/ensure-tart-cache-relay.nu`
  - ensures a relay exists on `192.168.64.1:443`
  - relays to `172.16.16.4:443`

- `runners/scripts/bootstrap-tart-cache.nu`
  - injects a guest `/etc/hosts` entry mapping the cache hostname to `192.168.64.1`
  - verifies `https://<cache-host>/up`

- `runners/scripts/run-tart-vm-with-private-cache.nu`
  - starts the VM if needed
  - waits for guest IP
  - kickstarts the managed relay once `bridge100` exists
  - bootstraps cache hostname mapping inside the guest

- `runners/scripts/cleanup-tart-cache.nu`
  - removes the temporary `/etc/hosts` entry from the guest

## Validated behavior

With a fresh NAT guest (`tuist-sequoia-proxytest`):

- guest could reach `https://github.com`
- host relay listened on `192.168.64.1:443`
- guest `/etc/hosts` entry for `tuist-01-test-cache.par.runners.tuist.dev` -> `192.168.64.1`
- guest could reach `https://tuist-01-test-cache.par.runners.tuist.dev/up`

## Important launchd caveat

The managed relay cannot bind `192.168.64.1:443` until Tart's `bridge100` interface exists.

Implication:

- a plain boot-time daemon start may fail with `Can't assign requested address`
- the relay should be managed by launchd, but kickstarted after the first VM starts on the host

That sequencing is now built into `run-tart-vm-with-private-cache.nu`.

For robustness, `ensure-tart-cache-relay.nu` also starts a one-shot fallback relay if the managed launchd service has not rebound the listener yet after kickstart.

## Why not the direct bridged-static-IP approach for now

That model was also partially validated:

- bridged guest + static `172.16.16.x` can hit `172.16.16.4` directly

But it is not the preferred implementation today because it adds extra complexity:

- per-VM private IP lease management
- guest private-route management
- guest DNS bootstrapping on macOS
- more operational risk when multiple VMs coexist

It remains a viable future optimization if direct guest private identity becomes necessary.

## Recommended next engineering step

Integrate the chosen model into the future Tart worker lifecycle:

1. ensure relay on host
2. boot NAT guest
3. inject cache hostname mapping into guest
4. run assignment
5. remove guest mapping during cleanup

This should live in the eventual runner worker/orchestrator layer, not in GitHub workflow YAML.
