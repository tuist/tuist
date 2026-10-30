# Amp Orbs on Tuist Linux sandboxes

This adapter implements [Amp's self-hosted Orb dispatch contract](https://ampcode.com/docs/orbs/self-hosted) using account-scoped Tuist sandbox operations. Managed connections use workload identity; standalone adapters use the account-admin API. Run `amp orb provider` on an always-on Linux controller with Bash, curl, jq, GNU coreutils (`timeout`), and outbound access to Amp and Tuist. Amp supplies spawn/pause/delete jobs; Tuist places each Orb in a Firecracker VM on the shared Linux fleet. No inbound connection from Amp or direct access to sandboxd's admin API is needed.

## Account integration on staging, canary and production

Account administrators connect Amp from **Settings → Integrations → Amp**. Register a provider in the Amp workspace and paste its `aop_live_…` token into Tuist. No Tuist CLI login, per-environment 1Password item, or operator-created provider is required. One connection serves one Tuist account; the same provider token cannot be connected to two accounts in one environment. Use distinct Amp registrations across environments. Anyone permitted to use that provider in Amp can run Orbs charged to the connected Tuist account. Canary and production retain the account's existing `sandboxes` flag; staging/development follow the sandbox substrate's default eligibility.

`amp_integrations` stores the account binding and Cloak-encrypted provider token. The UI never reads the saved token back, only a public status projection. Connect/replace/disconnect reauthorize the account administrator and persist an Oban reconciliation job in the same database transaction. A minute sweep repairs partial provisioning, observes provider availability and removes resources orphaned by account deletion.

The chart enables provisioning in a dedicated `tuist-amp-orbs` namespace. Each account connection gets a single-replica provider Deployment, Secret and ServiceAccount, named by integration UUID and credential revision. The outgoing consumer uses the Amp token; the dispatch adapter reads a fresh, kubelet-rotated, one-hour projected ServiceAccount token with audience `tuist-amp-orbs`. The internal dispatch endpoint requires TokenReview, the configured namespace, the exact current integration/revision identity and the current account binding. It authorizes only this connection's Orb operations. The workload identity never enters the guest. It receives no Kubernetes API RBAC and no default API-audience token. Runtime state is ephemeral; PostgreSQL owns the Orb mapping. Providers run unprivileged with a read-only root on the general amd64 pool.

A credential replacement advances the revision immediately, so the old workload is denied before its eventual removal. Disconnect removes the database token and denies dispatch immediately, then reconciliation removes provider resources and pauses its Orbs without deleting disks. Failed pauses remain visible and retry. Reconnecting preserves the integration's Orb mappings. Flag withdrawal denies new spawn operations immediately, allows cleanup until reconciliation stops the provider, and pauses its Orbs. Account deletion cascades integration data; the sandbox lifecycle and periodic provider sweep clean up runtime resources.

Cluster-wide integration locks serialize mutations, reconciliation and managed dispatch across connected web replicas, using the sandbox substrate’s existing locking contract. Lifecycle writes commit before node commands; no database transaction spans a VM operation. Kubernetes API operations are idempotent; a crashed reconciler is repaired by the next sweep. Reconciliation waits for terminating pods to disappear before starting a replacement consumer. The ServiceAccount acts as the provisioning/cleanup marker and is removed last, so partial Secret/Deployment writes remain discoverable. Do not force-delete an unreachable provider pod without fencing its host; Amp still permits one consumer per provider token.

Status **Provider running** means Kubernetes observes a ready consumer process, not a verified Amp handshake. Check the provider connection in Amp and run a thread for initial qualification. Provider stdout/stderr are suppressed because they may contain private thread data. Pending/error status and last-check time are persisted without private diagnostics. Local UI review without a configured provider image does not create a provider or connect to Amp.

The provider image contains pinned Amp plus Bash/curl/jq; it no longer contains the Tuist CLI or refresh-token machinery. The managed chart has no shared provider credentials, ExternalSecret or credential PVC. Previously created internal 1Password items are not consumed by this feature. If an older experimental deployment exists, stop it and revoke its dedicated Tuist login separately before removing any retained credential PVC.

## Standalone installation


1. Deploy the sandbox substrate and matching controller introduced by #12886, apply the `amp_orb_id` migration, and deploy this server. Normal server deployments publish the updated `infra/sandbox-image` template and select its immutable tag automatically (see below). Existing VMs keep their original rootfs; they do not gain Amp through a template upgrade.
2. Enable the account's `sandboxes` feature flag on canary or production; staging defaults to enabled. The existing five-live-sandbox limit includes paused Orbs. Arrange disk capacity before increasing that limit; long-lived Orbs continue to reserve their full disk ceiling.
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

Start `amp orb provider /opt/tuist-amp-orbs/dispatch.sh`. An example systemd service is in `provider.service`; keep exactly one provider per Amp token and stop the old process before starting its replacement. The dispatch adapter has no local Orb mapping to back up: `(account_id, amp_orb_id)` lives in PostgreSQL. The provider token stays on the controller; only Amp's short-lived per-Orb token and a read-only Tuist cache token (see below) reach its guest.

Choose this provider in Amp's new-thread Orb picker, or run `amp -ox 'your prompt' --orb-provider <provider-name>`. Amp clones the repository, applies `.agents/setup` and manages Git credentials. Tuist launches `amp orb bootstrap` as `user` with `/home/user` writable and passwordless sudo. `/home/user/workspace` points to `/workspace/amp` on the VM's separately budgeted workspace disk.

## Template deployment

`server-production-deployment.yml` treats guest image and publisher changes as deployable. Before canary, it calls `sandbox-image.yml` to test and publish the template, then passes the same `sandbox_template_image_tag` to canary and production through the existing acceptance gates. The existing hotfix path also requires a successfully published template. Staging is an independently dispatched server deployment; a fresh deployment builds/selects its template automatically too.

The tag is `sha-<12-character source commit>`, resolved from the last guest image, provider source, publisher workflow or version-resolver change reachable from the deployment commit. Unrelated server changes reuse the published image and do not roll sandboxd merely to change the template tag. Publication is serialized, existing tags are reused, and registry authentication/network failures stop the publisher. A new template tag changes the DaemonSet's init image and template directory; its rollout installs the image on each sandbox node. Existing Orb disks remain on their original guest image.

For a server-only rollback or re-promotion (`image_tag` supplied), the workflow preserves the template currently configured on sandboxd unless `sandbox_template_image_tag` is explicitly supplied. It fails if it cannot determine that live version; a first installation with a pre-built server must supply the template tag. The fixed template tags in managed Helm values are bootstrap defaults for direct chart users, overridden by normal deployments. The sandboxd daemon image remains separately pinned.

## Lifecycle and persistence


- **Spawn:** find/create by account and Orb ID, obtain a fleet admission grant at the same priority as CI, within the account’s separate sandbox CPU/RAM budget, resume if needed, record an active residency, then invoke Amp bootstrap with the new token. Retried jobs reuse the same VM. A placed VM in error is preserved for diagnosis rather than silently replaced. A failed placement without a node can be retried.
- **Active turn:** no Tuist wall-clock expiry. Residency protects the detached Amp process from idle pause and CI reclaim. Amp owns idle detection. If the provider is down, active Orbs can keep consuming RAM until it reconnects and delivers pause/delete; monitor provider availability and reconcile these explicitly.
- **Pause:** snapshot RAM and disks on the owning node, then release residency and reclaim RAM. Repeated pauses are harmless. Saved processes resume with the next turn. A failed snapshot retains residency so reclaim does not interrupt the Orb.
- **Retention:** Amp Orbs are exempt from the 14-day sandbox sweeper, including errored Orbs. They retain files until an explicit Amp/Tuist delete or deletion of the owning account. There is no promise of infinite storage: paused Orbs retain their disk reservation and count against the account limit.
- **Delete:** remove the sandbox and its database mapping. A repeated delete succeeds. If the node is away, the existing orphan reconciliation removes the jail when it reconnects.
- **Project snapshots:** a pause with `ORB_SNAPSHOT_ID` runs `sync` in the guest before the memory snapshot, then reflinks the Orb's rootfs and workspace disks into a disk snapshot on the same node (`sandbox_disk_snapshots` row, keyed by the account and Amp's ID). A spawn of a new Orb with that ID is placed on that node and cold boots on clones of those disks, so `.agents/setup` does not run again; `.agents/resume` restarts services, since a disk snapshot keeps no processes. Saving is best effort: a failed save or a full node disk budget still pauses the Orb, and the next new Orb runs setup. A newer save under the same ID replaces the older copy. When the snapshot's node cannot take the Orb, or the clone fails, the Orb boots from the template instead. Snapshots reserve their full ceiling against the node's disk budget and are deleted after 72 hours without use, matching Amp's reuse window. They exist only on one node's NVMe: there is no cross-node copy yet.

The control plane retains the base substrate's clustered-server lifecycle locking requirement. Dispatch for one account/Orb is serialized across the cluster, with a database unique index fencing identity. A concurrent job receives HTTP 409 and can be replayed. On spawn, the adapter retries only explicit admission refusals (fleet capacity, account CPU/RAM quota, or admission-lock contention), using exponential backoff with jitter and a stable Orb ID. It prints “Waiting for sandbox capacity or account CPU/RAM budget” in Amp’s setup log. Waiting happens outside server locks, and each attempt rechecks authorization and admission; managed workload tokens are reread on every attempt. Pause/delete, generic HTTP failures, and ambiguous transport errors are not automatically retried. Response bodies and credentials are never printed.

The admission retry window is 150 seconds from dispatch start, leaving two minutes for startup within a 270-second total HTTP budget and Amp’s five-minute deadline. Each HTTP request is capped at the remaining total budget (at most 240 seconds); an already-started boot may finish after the retry window. `TUIST_ORB_CAPACITY_WAIT_SECONDS` can shorten the retry window to 0–150 seconds (0 disables retries), but cannot extend it. On exhaustion the adapter reports a capacity timeout and asks the user to retry; it does not promise an indefinite queue or automatic replay by Amp. Older servers without the explicit `X-Tuist-Orb-Retry: admission` response header keep failing immediately, so deploy the server and provider changes together.

## Tuist cache access

Every spawn gives Amp's processes `TUIST_TOKEN`, `TUIST_URL` and, when the account has an in-cluster Kura node, `TUIST_CACHE_ENDPOINT`, so Tuist clients (including `tuist_ex` dependency caching) read the account's remote cache over the cluster network instead of compiling from scratch.

- **Credential:** a stateless signed token for the Orb's account with only `account:cache:read` and `project:cache:read`, valid for six hours. It reads the account's cache and discovers its endpoints; the API refuses it for cache writes and every other operation. Nothing about it is stored. Each spawn mints a new one, and a resumed Orb's fresh `ORB_TOKEN` restarts Amp with it. A retried spawn with the same `ORB_TOKEN` keeps the running process and its earlier token. Disconnecting the integration does not revoke issued tokens; they expire on their own.
- **Endpoint:** the same URL a Linux runner on the sandbox's Node receives (`Tuist.Kura.runner_cache_endpoint_url/3`, site from the Node's `node.cluster.x-k8s.io/rack-site` label). Guests reach it through the sandboxes NetworkPolicy's `kuraEgress` rule. A private runner-cache node is kept only for the account's CI jobs; when it drains, clients fall back to local compilation.
- **Failure modes:** an expired token, an unreachable endpoint or a refused write falls back to local work; it never fails a build. Processes started before a credential refresh keep their old environment.
- **Writes:** Orbs never populate the cache. Agents run arbitrary code, and a write credential would let any thread on the provider publish artifacts that the account's CI and developers then execute. Write access requires a separate, explicit per-integration choice.

## Limits and rollout checks

`ORB_IMAGE` is the **installed Firecracker template name**, not an OCI image reference. Set it in the provider environment as above. A mismatched image fails explicitly.

This image supports coding tools, portals and Terminal dependencies. Desktop is not included: it needs Amp's Wayland/browser stack. The guest is Linux amd64/glibc, uses `sbx-init` rather than systemd, and ships a pinned, checksum-verified Amp CLI. The guest helper serializes bootstrap launches, reuses the existing process for an identical token/URL, and replaces only the bootstrap PID for fresh credentials. Root-owned PID/start-time and credential-fingerprint state lives in `/run`, survives a memory snapshot, and disappears on cold boot. It neither stores a plaintext token nor signals unrelated background work.

Paused state lives only on the owning node's NVMe. This change does not add cross-node recovery or backups. A clean daemon restart saves memory; an abrupt restart cold-boots the surviving disks and loses processes/unflushed writes. Lost host storage can lose the Orb. Indefinite retention is not a durability guarantee.

Allow outbound HTTPS/WSS to `ampcode.com`, `static.ampcode.com`, `tunnel.ampcode.com` and the Git host, plus any required project dependencies. Proxies must support long-lived connections. Custom `AMP_URL` values must use HTTPS. Existing sandbox egress policy still applies.

Before enabling a real workspace, use staging to run a thread that writes a file and starts a background counter, pause it, restart the provider, and continue the thread. Verify the same sandbox ID, retained file and process, released RAM while paused, admission alongside queued CI, refusal at the independent account CPU/RAM limit, recovery when capacity frees during the bounded wait, and repeatable deletion. Exercise daemon restart separately. Local fake-node and container checks do not establish KVM, full Amp handshake or multi-host behavior.

Rollback: stop the provider, explicitly pause active Orbs, and retain their rows and jail directories. **Do not roll back to a server without the Amp retention exemption while Orbs exist**, because its sweeper would delete old Orbs. Keep the additive column/index until all Orbs are explicitly removed. Managed overlays enable the provider; standalone chart defaults keep it disabled. Account administrators connect their own providers through the Integrations page after deployment.

## Isolated KVM validation

`Sandbox Orbs Isolated Validation` runs on a disposable GitHub-hosted Ubuntu VM with `/dev/kvm`, independently of staging and the managed runner fleet. It builds the guest and daemon without publishing either, installs the guest on a private XFS reflink filesystem, and exercises the real jailer, Firecracker, guest agent and bootstrap helper. It checks duplicate bootstrap, file and process preservation across memory snapshots, fresh-token bootstrap replacement, a clean daemon restart, and repeated deletion. Logs and lifecycle responses are uploaded as a seven-day artifact; the containers, guests and loop filesystem are removed on exit.

The checked-in driver is deliberately restricted to GitHub-hosted disposable runners because it needs privileged Docker, a loop device and mounts. GitHub Actions is a convenient isolated host, not a requirement of Amp or Tuist. A dedicated x86 Linux KVM host can run the same setup after adapting that environment guard and temporary-directory settings; do not point this test at a shared sandbox daemon.

This credential-free check substitutes only the Amp bootstrap process inside its disposable guest. It proves real VM lifecycle behavior, not an authenticated Amp connection, the Tuist HTTP/database path, fleet admission or Kubernetes rollout. A complete live test additionally needs an isolated Tuist control plane and a dedicated Amp provider. Register it in workspace Settings → Orbs, retain its provider token privately, and choose it explicitly in a new test thread. An Amp API key is only needed to automate sending messages; a human can send them through the UI. The PR validation job never receives Amp credentials.

### Authenticated isolated validation

Manually dispatch the same workflow with `live_amp=true` and a dedicated provider token in the temporary repository secret `AMP_ORB_ISOLATED_VALIDATION_TOKEN`. Remove that secret after the run. For the staging provider, the source credential is the `Amp Orb Provider` password item in the `tuist-k8s-staging` 1Password vault; storing it there does not start a staging provider. Stop any existing provider using the token before this test.

This mode starts disposable PostgreSQL/ClickHouse databases, the actual Tuist HTTP endpoint in test configuration, a kind Kubernetes API for genuine ServiceAccount TokenReview, and sandboxd with real Firecracker. The daemon runs outside kind with a token bound to its temporary identity Pod. It uses fixed memory capacity; the managed runner controller and elastic fleet admission are outside this check. No shared cluster is contacted and no images are published. Only the manually dispatched live step receives the Amp secret.

When the job prints `READY`, select that provider explicitly in Amp and start one disposable thread. Send `Run echo first-turn > /workspace/amp/from-amp-first and report success`, then Archive the thread to pause its Orb. The job verifies released residency and no remaining VMM, restarts the provider, and prints the second `READY`. Continue the same thread with `Read /workspace/amp/from-amp-first, then run echo second-turn > /workspace/amp/from-amp-second and report success`; leave it running until the job confirms both markers, then Archive it. The observer checks the same PostgreSQL mapping and an independently started process's PID, start time and advancing counter across resume. It deletes the test sandbox twice through the production adapter, checks the mapping is gone, and removes its local infrastructure. Delete the disposable Amp thread afterwards; its VM no longer exists.

The interactive phase times out after 30 minutes and cleans up on exit. Logs/artifacts contain selected lifecycle metadata, not provider logs, guest consoles, environment files, kubeconfigs or credentials. This does not validate the production build/configuration, multi-replica behavior, fleet-controller admission or a Kubernetes rollout. The normal PR job remains credential-free.

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
