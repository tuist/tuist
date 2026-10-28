# Amp Orbs on Tuist Linux sandboxes

This adapter implements [Amp's self-hosted Orb dispatch contract](https://ampcode.com/docs/orbs/self-hosted) using the account-admin Tuist sandbox API. Run `amp orb provider` on an always-on Linux controller with Bash, curl, jq, GNU coreutils (`timeout`), and outbound access to Amp and Tuist. Amp supplies spawn/pause/delete jobs; Tuist places each Orb in a Firecracker VM on the shared Linux fleet. No inbound connection from Amp or direct access to sandboxd's admin API is needed.

## Managed staging, canary and production

The managed Helm overlays deploy one outgoing provider per environment as part of the server release. It uses `https://staging.tuist.dev`, `https://canary.tuist.dev`, or `https://tuist.dev`, and the `tuist` organization (`ampOrbProvider.account`). This account owns the sandbox rows, quota and administrator access; it is separate from the Amp user creating a thread. This managed deployment serves our internal organization only: enabling another organization’s sandbox flag does not register an Amp provider or route jobs to that organization. Other organizations can run the standalone adapter with their own provider/account credentials; managed account onboarding is not implemented here. Canary and production still require that account's `sandboxes` feature flag. Staging defaults to enabled.

Before merging/enabling the provider, provision these two Password items in **each** corresponding `tuist-k8s-staging`, `tuist-k8s-canary`, and `tuist-k8s-production` vault:

| Item | `password` contents |
| --- | --- |
| `Amp Orb Provider` | The token from a distinct Amp provider registered for that environment |
| `Amp Orb Tuist Credentials` | A dedicated Tuist account-admin CLI login, stored as credential JSON by the helper below |

The existing `tuist-orbs` registration can be used for staging; register separate canary/production providers. Never run two environments or an isolated test with the same Amp provider token. The environment-local `onepassword` ClusterSecretStore syncs the two items through an ExternalSecret. Missing items block provider readiness and therefore the waited Helm rollout; provision them before deployment, or explicitly keep `ampOrbProvider.enabled=false` until ready.

From a checkout with `tuist`, `op`, Bash and jq available, run these interactively, signing in as an administrator of the configured organization:

```sh
bash infra/amp-orbs/store-credentials.sh staging
bash infra/amp-orbs/store-credentials.sh canary
bash infra/amp-orbs/store-credentials.sh production
```

The helper creates an isolated CLI login, saves it directly into the correct vault without printing credentials or passing them as command arguments, and removes the temporary local session. It creates or updates only the `Amp Orb Tuist Credentials` item. Do not copy a session actively used by a developer CLI: its rotating refresh token would be shared by two independent stores. Run the helper again to replace revoked or expired authorization with a fresh dedicated login.

The provider image pins and verifies Amp and Tuist CLI downloads. The provider runs as UID 10001 on the general amd64 node pool, with a read-only root filesystem, no Kubernetes API token or RBAC, and no inbound Service. Amp needs executable temporary storage for its bundled native modules. Only outbound HTTPS/WSS to Amp and HTTPS to the configured Tuist origin are needed by this controller.

A single-replica `Recreate` Deployment stops the old consumer before starting a replacement; the PVC also has a process lock. Do not scale it up or force-delete a pod on an unreachable node without first fencing that node's process. A 300-second termination grace period allows dispatch shutdown. Tuist credentials are refreshed via the existing CLI at startup, every 15 minutes while idle, and for each dispatch. The writable 1 GiB PVC retains rotated credentials across pod restarts. The initial Secret is copied only once or when a new login changes its hash; restarting never overwrites a rotated session with the spent seed. The volume is bound to its origin and organization and is retained when Helm disables/removes the provider. Lost credential storage requires a **fresh login**, not restoring the original seed from 1Password. Treat the PVC as sensitive and delete it explicitly when decommissioning the provider after handling its Orbs.

Secret projections are checked every five seconds; after ESO and kubelet propagate a token/login change, the supervisor stops the consumer and Kubernetes starts it with the new values. Private Amp output and token-refresh diagnostics are not shipped to cluster logs. Generic authentication/restart errors remain visible. Readiness means a recent successful Tuist token resolution, not proof of an Amp WebSocket connection: verify the selected provider is connected in Amp and execute a real thread for initial qualification. Normal pod availability/restart monitoring applies; an unavailable provider can leave active Orbs retaining RAM.

The reusable sandbox publisher builds and validates the provider container alongside the guest, then publishes both immutable images before deployment can proceed. The provider is published in the existing `ghcr.io/tuist/tuist-sandbox-template` package with the `-provider` tag suffix, reusing that package’s pull visibility and permissions instead of introducing a new private-by-default package. Helm derives both image tags from the selected `sandboxes.templateImage.tag`. Provider source changes participate in that version and in the server deploy path filter. Canary and production promote the pair together; a fresh staging server deployment publishes/selects it too. A server-only rollback preserves the selected pair. Do not enable this provider against an older template tag that predates paired publication.

After rollout, use a fresh disposable thread in each selected Amp provider. Verify setup succeeds, write a marker, **Archive** the thread to pause, confirm residency/RAM release, restart the provider, reopen the same thread and verify its file and background process before writing the second marker. Archive again after observing the second marker. Check the same sandbox ID and repeat deletion. Pause/delete Orbs **before** disabling the account flag: the flag also gates cleanup requests and does not terminate existing VMs.

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

Start `amp orb provider /opt/tuist-amp-orbs/dispatch.sh`. An example systemd service is in `provider.service`; keep exactly one provider per Amp token and stop the old process before starting its replacement. The dispatch adapter has no local Orb mapping to back up: `(account_id, amp_orb_id)` lives in PostgreSQL. The provider token stays on the controller; only Amp's short-lived per-Orb token reaches its guest.

Choose this provider in Amp's new-thread Orb picker, or run `amp -ox 'your prompt' --orb-provider <provider-name>`. Amp clones the repository, applies `.agents/setup` and manages Git credentials. Tuist launches `amp orb bootstrap` as `user` with `/home/user` writable and passwordless sudo. `/home/user/workspace` points to `/workspace/amp` on the VM's separately budgeted workspace disk.

## Template deployment

`server-production-deployment.yml` treats guest image and publisher changes as deployable. Before canary, it calls `sandbox-image.yml` to test and publish the template, then passes the same `sandbox_template_image_tag` to canary and production through the existing acceptance gates. The existing hotfix path also requires a successfully published template. Staging is an independently dispatched server deployment; a fresh deployment builds/selects its template automatically too.

The tag is `sha-<12-character source commit>`, resolved from the last guest image, provider source, publisher workflow or version-resolver change reachable from the deployment commit. Unrelated server changes reuse the published image and do not roll sandboxd merely to change the template tag. Publication is serialized, existing tags are reused, and registry authentication/network failures stop the publisher. A new template tag changes the DaemonSet's init image and template directory; its rollout installs the image on each sandbox node. Existing Orb disks remain on their original guest image.

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

Rollback: stop the provider, explicitly pause active Orbs, and retain their rows and jail directories. **Do not roll back to a server without the Amp retention exemption while Orbs exist**, because its sweeper would delete old Orbs. Keep the additive column/index until all Orbs are explicitly removed. Managed overlays enable the provider; standalone chart defaults keep it disabled. Provision the managed credentials before deployment as described above.

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
