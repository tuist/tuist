# Amp Orbs on Tuist Linux sandboxes

This adapter implements [Amp's self-hosted Orb dispatch contract](https://ampcode.com/docs/orbs/self-hosted) using the account-admin Tuist sandbox API. Run `amp orb provider` on an always-on Linux controller with Bash, curl, jq, GNU coreutils (`timeout`), and outbound access to Amp and Tuist. Amp supplies spawn/pause/delete jobs; Tuist places each Orb in a Firecracker VM on the shared Linux fleet. No inbound connection from Amp or direct access to sandboxd's admin API is needed.

## Install

1. Deploy the sandbox substrate and matching controller introduced by #12886, apply the `amp_orb_id` migration, and deploy this server. Normal server deployments publish the updated `infra/sandbox-image` template and select its immutable tag automatically (see below). Existing VMs keep their original rootfs; they do not gain Amp through a template upgrade.
2. Enable the account's `sandboxes` feature flag. The existing five-live-sandbox limit includes paused Orbs. Arrange disk capacity before increasing that limit; long-lived Orbs continue to reserve their full disk ceiling.
3. Install Amp and Tuist on the controller, together with Bash, curl and jq. Create the `amp-provider` service user with a writable home and authenticate it with `tuist auth login --url <Tuist URL>` as an account administrator. With `TUIST_TOKEN` unset, each dispatch uses `tuist auth token --url` to refresh credentials through the CLI; revoked authorization still requires a new login. In Amp workspace Settings → Orbs, add a provider and store its token in the controller's secret environment. Use an account administrator's Tuist bearer token for the API, not a project/CI credential.
4. Install `dispatch.sh` at `/opt/tuist-amp-orbs/dispatch.sh`, executable. Supply the following environment through your service manager's protected environment file:

```sh
AMP_ORB_PROVIDER_TOKEN=<Amp provider token>
TUIST_URL=https://tuist.dev
TUIST_ACCOUNT=<account handle>
# Optional fixed bearer; if set, arrange rotation before it expires.
# TUIST_TOKEN=<Tuist account administrator user bearer token>
ORB_IMAGE=default
TUIST_ORB_TEMPLATE=default
TUIST_ORB_VCPUS=2
TUIST_ORB_MEMORY_MB=4096
TUIST_ORB_WORKSPACE_GB=10
```

Start `amp orb provider /opt/tuist-amp-orbs/dispatch.sh`. An example systemd service is in `provider.service`; keep exactly one provider per Amp token and stop the old process before starting its replacement. The dispatch adapter has no local Orb mapping to back up: `(account_id, amp_orb_id)` lives in PostgreSQL. The provider token stays on the controller; only Amp's short-lived per-Orb token reaches its guest.

Choose this provider in Amp's new-thread Orb picker, or run `amp -ox 'your prompt' --orb-provider <provider-name>`. Amp clones the repository, applies `.agents/setup` and manages Git credentials. Tuist launches `amp orb bootstrap` as `user` with `/home/user` writable and passwordless sudo. `/home/user/workspace` points to `/workspace/amp` on the VM's separately budgeted workspace disk.

## Template deployment

`server-production-deployment.yml` treats guest image and publisher changes as deployable. Before canary, it calls `sandbox-image.yml` to test and publish the template, then passes the same `sandbox_template_image_tag` to canary and production through the existing acceptance gates. The existing hotfix path also requires a successfully published template. Staging is an independently dispatched server deployment; a fresh deployment builds/selects its template automatically too.

The tag is `sha-<12-character source commit>`, resolved from the last guest image, publisher workflow or version-resolver change reachable from the deployment commit. Unrelated server changes reuse the published image and do not roll sandboxd merely to change the template tag. Publication is serialized, existing tags are reused, and registry authentication/network failures stop the publisher. A new template tag changes the DaemonSet's init image and template directory; its rollout installs the image on each sandbox node. Existing Orb disks remain on their original guest image.

For a server-only rollback or re-promotion (`image_tag` supplied), the workflow preserves the template currently configured on sandboxd unless `sandbox_template_image_tag` is explicitly supplied. It fails if it cannot determine that live version; a first installation with a pre-built server must supply the template tag. The fixed template tags in managed Helm values are bootstrap defaults for direct chart users, overridden by normal deployments. The sandboxd daemon image remains separately pinned.

## Lifecycle and persistence


- **Spawn:** find/create by account and Orb ID, obtain the usual CI-first admission grant, resume if needed, record an active residency, then invoke Amp bootstrap with the new token. Retried jobs reuse the same VM. A placed VM in error is preserved for diagnosis rather than silently replaced. A failed placement without a node can be retried.
- **Active turn:** no Tuist wall-clock expiry. Residency protects the detached Amp process from idle pause and CI reclaim. Amp owns idle detection. If the provider is down, active Orbs can keep consuming RAM until it reconnects and delivers pause/delete; monitor provider availability and reconcile these explicitly.
- **Pause:** snapshot RAM and disks on the owning node, then release residency and reclaim RAM. Repeated pauses are harmless. Saved processes resume with the next turn. A failed snapshot retains residency so reclaim does not interrupt the Orb.
- **Retention:** Amp Orbs are exempt from the 14-day sandbox sweeper, including errored Orbs. They retain files until an explicit Amp/Tuist delete or deletion of the owning account. There is no promise of infinite storage: paused Orbs retain their disk reservation and count against the account limit.
- **Delete:** remove the sandbox and its database mapping. A repeated delete succeeds. If the node is away, the existing orphan reconciliation removes the jail when it reconnects.

The control plane retains the base substrate's clustered-server lifecycle locking requirement. Dispatch for one account/Orb is serialized across the cluster, with a database unique index fencing identity. A concurrent job receives HTTP 409 and can be replayed. The adapter bounds HTTP calls to four minutes, inside Amp's five-minute dispatch deadline. Capacity refusal remains a failed job for Amp to retry, not a bypass of CI priority.

## Limits and rollout checks

`ORB_IMAGE` is the **installed Firecracker template name**, not an OCI image reference. Set it in the provider environment as above. A mismatched image fails explicitly. `ORB_SNAPSHOT_ID` is intentionally ignored: new threads start from the installed template and rerun project setup; the same Orb still resumes its own saved disk and memory. Project snapshot cloning needs a separate substrate feature.

This image supports coding tools, portals and Terminal dependencies. Desktop is not included: it needs Amp's Wayland/browser stack. The guest is Linux amd64/glibc, uses `sbx-init` rather than systemd, and ships a pinned, checksum-verified Amp CLI. The guest helper serializes bootstrap launches, reuses the existing process for an identical token/URL, and replaces only the bootstrap PID for fresh credentials. Root-owned PID/start-time and credential-fingerprint state lives in `/run`, survives a memory snapshot, and disappears on cold boot. It neither stores a plaintext token nor signals unrelated background work.

Paused state lives only on the owning node's NVMe. This change does not add cross-node recovery or backups. A clean daemon restart saves memory; an abrupt restart cold-boots the surviving disks and loses processes/unflushed writes. Lost host storage can lose the Orb. Indefinite retention is not a durability guarantee.

Allow outbound HTTPS/WSS to `ampcode.com`, `static.ampcode.com`, `tunnel.ampcode.com` and the Git host, plus any required project dependencies. Proxies must support long-lived connections. Custom `AMP_URL` values must use HTTPS. Existing sandbox egress policy still applies.

Before enabling a real workspace, use staging to run a thread that writes a file and starts a background counter, pause it, restart the provider, and continue the thread. Verify the same sandbox ID, retained file and process, released RAM while paused, admission refusal under queued CI, and repeatable deletion. Exercise daemon restart separately. Local fake-node and container checks do not establish KVM, full Amp handshake or multi-host behavior.

Rollback: stop the provider, explicitly pause active Orbs, and retain their rows and jail directories. **Do not roll back to a server without the Amp retention exemption while Orbs exist**, because its sweeper would delete old Orbs. Keep the additive column/index until all Orbs are explicitly removed. No cluster overlay enables this provider automatically.

## Local validation

```sh
node --test infra/amp-orbs/dispatch.test.mjs
# Includes Helm rendering; mise supplies the pinned helm/yq tools.
mise exec -- node --test .github/scripts/sandbox-deployment.test.mjs
bash -n infra/amp-orbs/dispatch.sh infra/sandbox-image/orb-bootstrap.sh
# From server/, with isolated test databases:
mix test test/tuist/sandboxes/amp_orbs_test.exs \
  test/tuist/sandboxes/workers/retention_worker_test.exs \
  test/tuist_web/controllers/api/sandboxes_controller_test.exs
```
