# macOS sandboxing prior art

## Product requirement framing

For a service that runs workflows for multiple users and organizations, bare-metal persistent runners are not a sufficient long-term isolation boundary.

They are fine for:

- internal Tuist CI experiments
- single-tenant bring-up
- validating cache connectivity and host bootstrap

They are weak for:

- cross-tenant workload isolation
- filesystem hygiene between runs
- simulator/device state isolation
- strong revocation and incident containment

## Strongest prior art: Tart

`cirruslabs/tart` is the strongest existing prior art for macOS per-run isolation on Apple Silicon.

Key properties:

- built on Apple's `Virtualization.Framework`
- runs macOS VMs on Apple Silicon
- VM images can be cloned from OCI registries
- clearly designed for CI use cases

Why it matters here:

- VM-per-run is the cleanest way to get from "host bootstrap" to "service isolation"
- it maps well onto self-hosted GitHub runner lifecycle patterns
- live validation on the test Mac confirmed the CLI installs and exposes the right VM/network primitives
- live boot attempts also exposed an important operational prerequisite: newer macOS hosts may need an unlocked login keychain and/or GUI session before VMs can start headlessly

## Fleet orchestration prior art: Orchard

`cirruslabs/orchard` is the best open orchestration example sitting on top of Tart.

Relevant findings:

- it treats Apple Silicon hosts as workers in a cluster
- it exists specifically to manage many macOS VMs across bare-metal hosts
- on macOS 15+, local network permissions create extra operational complexity

Important Orchard note:

- on recent macOS, worker networking may require a small privileged helper or a system-level local-network privacy workaround

Implication:

- a multi-tenant service should expect host-level network/privacy configuration work if it uses VM-backed runners

## Supplemental hardening prior art: nono

`always-further/nono` is not a VM orchestrator. It is a syscall/path-level sandbox layer.

Useful properties:

- supports macOS via Seatbelt
- path-level allow/deny policy
- can block writes outside explicit allowlists
- very low startup overhead

Important limitation for Tuist's use case:

- nono is not a strong multi-tenant execution boundary by itself
- it does not replace VM-backed isolation for untrusted workflows from different customers

Best fit in this architecture:

- defense-in-depth inside a guest VM
- hardening host-side helper processes
- protecting local tooling during bootstrap or maintenance tasks

## Practical Tuist interpretation

### Week 1

- keep the host as a persistent bootstrap node
- do not claim strong multi-tenant isolation yet
- focus on dynamic registration, account scoping, and cleanup discipline

### Phase 2

- use the host as a VM worker
- spin an isolated macOS VM per assignment or per small trust domain
- register runners dynamically from inside the VM or immediately before handing work to it

### Phase 3

- move to a full pool scheduler where `server/` leases VM capacity per account/project
- garbage-collect VMs and runner state after each assignment

## Constraints on the current test machine

- Apple M1
- 8 GB RAM

This is enough for:

- bootstrap experiments
- maybe a small number of lightweight VMs

This is not a comfortable long-term host size for:

- high-concurrency VM-per-run service use
- multiple simultaneous simulator-heavy jobs

It also currently has a practical operability constraint:

- Tart guests do not boot headlessly over SSH on a cold host state here.
- A real GUI login session for `m1` did unblock guest boot.
- The documented keychain workaround alone was not sufficient on this particular host.
- An autologin-backed or otherwise durable GUI session model is likely required for unattended VM execution on this hardware.

It also currently has a network constraint:

- default NAT alone does not reach the cache over the private `172.16.16.0/22` path
- direct bridging to `vlan0` does work for the private path if the guest is given a static `172.16.16.x` address
- bridged guests therefore need explicit per-VM IP allocation/bootstrap instead of relying on DHCP

## Recommendation

- Keep `/runners` focused on deterministic host bootstrap.
- Keep `server/` focused on dynamic registration and tenancy.
- Treat Tart/Orchard-style VM isolation as the likely product direction for real multi-tenant execution.
- Treat nono as a possible extra hardening layer, not the primary isolation boundary.
- Do not over-invest in making persistent bare-metal runners look safer than they are.

For this test host specifically:

- Tart is promising but not yet production-ready until the headless keychain/session issue is solved.
