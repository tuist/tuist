# Tart runner worker lifecycle

## Goal

Turn the validated Tart + private-cache model into a concrete host-worker lifecycle that the future `server/` control plane can drive.

## Chosen execution model

- one physical Mac host runs a worker loop
- each assignment gets a disposable Tart clone
- the guest stays on Tart NAT
- the host exposes the cache privately through the managed relay on `192.168.64.1:443`
- the guest gets a temporary `/etc/hosts` override for the cache hostname
- the guest is destroyed after the assignment

## Host-side lifecycle steps

### 1. Lease assignment from `server/`

Expected server payload shape:

- `assignment_id`
- `base_vm`
- `cache_host`
- `registration_mode`
- `registration_payload` or endpoint to fetch it
- job metadata and labels

### 2. Clone disposable VM

Script:

- `runners/scripts/create-tart-assignment-vm.nu`

Behavior:

- clones from the chosen base image to `tuist-assignment-<id>`

### 3. Start and prepare the VM

Scripts:

- `runners/scripts/run-tart-vm-with-private-cache.nu`
- `runners/scripts/normalize-tart-guest-network.nu`
- `runners/scripts/ensure-tart-cache-relay.nu`
- `runners/scripts/bootstrap-tart-cache.nu`

Behavior:

- starts the VM headlessly
- waits for `tart exec` readiness
- normalizes the guest back to DHCP/default NAT if a base image was previously dirtied
- kickstarts the managed host relay and falls back to a one-shot relay if necessary
- injects guest cache hostname mapping

### 4. Register runner dynamically

Host-side staging is now implemented:

- host requests assignment-specific registration material from `server/`
- server returns short-lived token or JIT config in the assignment payload
- guest writes the material to runtime-only paths via `stage-tart-assignment-registration.nu`
- guest then needs to register the GitHub runner inside the VM

Validated result on the test host:

- the disposable clone stays alive through cache bootstrap and registration staging when launched through the fixed detached worker path

### 5. Execute assignment payload

Script:

- `runners/scripts/exec-tart-assignment.nu`

Behavior:

- runs a command inside the guest using `tart exec`

For the product path this should become:

- start the runner process inside the guest
- wait for GitHub to hand over the job

### 6. Cleanup and destroy

Scripts:

- `runners/scripts/cleanup-tart-cache.nu`
- `runners/scripts/destroy-tart-assignment-vm.nu`

Behavior:

- removes temporary cache hostname override
- stops the VM if it is still running
- deletes the clone

## Validated proof on the test Mac

The checked-in scripts were validated with a disposable assignment-shaped VM:

1. create clone
2. run with private cache bootstrap
3. stage registration material from a payload
4. verify staged runtime files inside the guest
5. destroy clone

Result:

- disposable worker lifecycle works end to end on the test host
- payload-driven registration staging works inside the disposable guest

## Important base-image rule

Do not mutate the long-lived base VM during experiments or provisioning.

Why:

- clones inherit guest network configuration changes
- the worker therefore now includes guest network normalization as a safety measure

But operationally the better rule is:

- keep a sealed golden base image
- make all assignment-specific changes only in disposable clones

## Recommended server integration contract

### Host worker inputs from `server/`

- assignment id
- base image name
- GitHub registration material or a fetch endpoint
- repository/project metadata
- cache hostname
- allowed runtime budget

See also:

- `.discovery/plans/runner-assignment-payload-contract.md`

### Host worker outputs back to `server/`

- clone created
- guest ready
- runner registered
- job started
- job completed / failed / cancelled
- guest destroyed

## Recommended next step

The next server-side work should implement an assignment payload that maps directly onto this worker lifecycle.

The host-side primitives are now concrete enough to drive from `server/`.
