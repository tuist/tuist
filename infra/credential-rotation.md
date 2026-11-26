# Platform credential inventory and rotation

Every credential the managed Tuist platform holds, where it lives, what reads
it, and how to replace it. Use it in two situations:

- **One credential leaked.** Find its row, follow its procedure, restart what
  the row says.
- **Assume everything leaked** (the Bitrise November 2026 case: an internal
  system with reach into platform secrets). First contain with
  [incident-containment.md](incident-containment.md), then rotate in the
  [order below](#rotation-order). Recovery time is set by how fast this list
  can be worked through, so rehearse it on staging.

This document does not grant access. Agents follow
[Cluster access for agents](AGENTS.md#cluster-access-for-agents): they never
read Secrets, never fetch admin kubeconfigs and never approve elevations.
Every step below that reads or writes a Secret, 1Password item or cloud console
is done by a person. Never print a credential into a terminal that is being
recorded, a CI log (Actions logs are public) or a thread.

The inventory was built from the repository on 2026-11-16 by rendering the
managed overlays (`helm template` of `helm/tuist` with
`values-managed-common.yaml` + `values-managed-production.yaml`, and of the
other charts with their production values). What the repository cannot show is
marked **unverified**: 1Password service-account scopes, GitHub organization
and environment settings, and cloud-console state. Re-render when charts change:

```bash
helm template tuist infra/helm/tuist -n tuist \
  -f infra/helm/tuist/values-managed-common.yaml \
  -f infra/helm/tuist/values-managed-production.yaml \
  -f infra/helm/tuist/values-ci.yaml \
  | yq ea 'select(.kind=="ExternalSecret") | [.spec.target.name // .metadata.name,
      ([.spec.data[]?.remoteRef.key] + [.spec.dataFrom[]?.extract.key] | unique | join(","))]
      | join(" <- ")'
```

## How a rotation reaches a running pod

Almost every platform secret follows the same path:
**1Password item → ESO `ExternalSecret` → Kubernetes Secret → pod**.

1. **Edit the item** in the environment's vault (`tuist-k8s-staging`,
   `tuist-k8s-canary`, `tuist-k8s-production`; `tuist-k8s-mgmt` for the
   management cluster; `atlas-k8s-production` for Atlas). Each environment has
   its own item; rotate them separately and never copy a value between envs.
2. **Sync it.** `ExternalSecret`s refresh every hour (`refreshInterval: 1h`;
   the rack borrower kubeconfigs every 5 minutes). To sync now:

   ```bash
   kubectl -n <ns> annotate externalsecret <name> force-sync="$(date +%s)" --overwrite
   kubectl -n <ns> get externalsecret <name>   # wait for SecretSynced / Ready=True
   ```

   `tuist-server-cluster-cookie` uses `refreshPolicy: OnChange` and **only**
   syncs on that annotation (see [onboarding §5e](k8s/onboarding.md#5e-durable-server-distribution-cookies)).
3. **Restart the consumers.** The Tuist chart has no Secret checksum
   annotations and no reloader. Everything that takes a Secret as an env var
   (`envFrom` / `secretKeyRef`, which is nearly everything here) keeps the old
   value until its pods are recreated:

   ```bash
   kubectl -n <ns> rollout restart deployment/<name>
   kubectl -n <ns> rollout status deployment/<name>
   ```

   The exceptions are called out in the tables: CNPG reconciles role passwords
   itself, and controllers that read a Secret through the API pick up changes
   on their next reconcile.
4. **Revoke the old value at its issuer** (cloud console, GitHub, Stripe…)
   only after every consumer runs with the new one. For a leak, revoke first and
   accept the outage; the order is the difference between a planned and an
   emergency rotation.

On canary and production, steps 2 and 3 are writes: they need a human
elevation (`/elevate`) whose intent names the rotation. Staging writes are
open. Neither tier can read Secrets, which is fine: none of these steps reads
one.

Release and namespace names: production is release `tuist` in namespace
`tuist`; staging and canary are release `tuist` in `tuist-staging` /
`tuist-canary`. Objects are named `tuist-tuist-<component>` (for example
`tuist-tuist-server`, `tuist-tuist-server-config-external-secrets`).

## Rotation order

Rotate in tiers. Each tier holds credentials that grant access to the tiers
below it, so rotating a lower tier first only hands the attacker the new value.

| Tier | What | Why first |
| --- | --- | --- |
| 0 | Contain ([incident-containment.md](incident-containment.md)) | Stop the bleeding and preserve evidence before anything changes. |
| 1 | People and roots of trust: 1Password accounts and service accounts, GitHub organization owners, Google Workspace admins, cloud-console logins | Every other secret is readable through these. |
| 2 | Cluster access: CI deployer credentials, admin kubeconfigs, the management cluster's CAPI secrets, then cluster CAs and ServiceAccount signing keys if a control plane or etcd is suspected | Cluster admin reads every Secret below. |
| 3 | Infrastructure API keys: Hetzner, OVH, Vultr, Scaleway, Cloudflare, Tailscale, AWS Route53, Tigris/S3, Grafana Cloud | Control of machines, DNS, and storage. |
| 4 | Server root keys: `SECRET_KEYS` (base, tokens, cache_tokens; see the notes on `password` and `encryption`), Kura volume keys, license and grant keys | Forge sessions and tokens, decrypt stored customer secrets. |
| 5 | Databases, object storage, internal apps (tuist-ops, Atlas, Pomerium, MDM, Slack invite, Typesense) | Data access. |
| 6 | Third-party integrations: GitHub Apps, OAuth clients, Stripe, Slack, Apple, APNs/FCM, mail, Sentry, Turnstile | External blast radius, mostly self-contained. |
| 7 | Customer-held credentials: legacy user/project tokens, customer secrets stored in Tuist | Needs customer notice; see [Customer-facing](#tier-7-customer-facing-credentials). |

Within a tier, do staging first when time allows: it proves the procedure on
the same charts.

## Splitting reused secrets

One value used for two purposes means one leak exposes both, and one rotation
breaks both. Each purpose gets its own secret, and each split keeps the old
value valid until every consumer has moved, as the OWASP
[Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
recommends ("Often, services share the same secrets, which makes identifying the
source of compromise or leak challenging"; §2.4 gradual rotation, new keys for
writes and old keys for reads). The code for each split is in place and is a
no-op until the steps below are taken. Every step that creates a 1Password item
or changes production needs Pedro's or Marek's approval.

| Reuse | Split to | Steps, in order |
| --- | --- | --- |
| Server `SECRET_KEYS`: `password` and `tokens` fall back to `base` when unset (`Tuist.Environment.secret_key_password/1`, `secret_key_tokens/1`) | Three distinct fields | Fields are synced in production and canary; whether any equals `base` is unverified. (1) A person compares `base`, `password` and `tokens` in 1Password without copying them anywhere. (2) If `tokens` equals `base`: rotate `tokens` with `tokens_previous` ([Tier 4](#tier-4-server-root-keys)). (3) If `password` equals `base`: change **`base`** instead (`password` is the bcrypt pepper and cannot change); it signs everyone out of the dashboard and invalidates everything else `Phoenix.Token` signs or encrypts under `base`: queued `DeleteAccountArtifactsWorker` and sandbox archive-copy deletion jobs (their storage argument is encrypted; drain those queues first or deleted accounts' artifacts are not purged), runner job report tokens (GitHub, Buildkite, Bitrise; up to 12 h), queued confirmation emails, preview install and build-trace links, and GitHub or Slack connections in progress. (4) Only then push and deploy the boot guard (`Tuist.Environment.validate_secret_keys!/2`, shipped as its own commit after the rest); it fails in the canary migration Job before any pod restarts if a step was missed. Staging is not guarded, so it gives no early warning. |
| `SECRET_KEYS/tokens` is also the Kamal cache's `GUARDIAN_SECRET_KEY` (vault `cache`) while `cacheTokenKey.signing` is off: whoever reads vault `cache` can mint server user tokens | Cache holds only the ES256 public key (`CACHE_TOKEN_PUBLIC_KEY`) | (1) `server.config.cacheTokenKey.enabled: true` per env with `SECRET_KEYS/cache_tokens` set, deploy. (2) Put the public half in vault `cache` as `CACHE_TOKEN_PUBLIC_KEY`, add it to `cache/config/deploy.yml` and `.kamal/secrets.*`, deploy the cache. (3) `cacheTokenKey.signing: true`, deploy. (4) Remove `GUARDIAN_SECRET_KEY` from the cache config and vault `cache`, deploy the cache. (5) Rotate `SECRET_KEYS/tokens` in the [Tier 4](#tier-4-server-root-keys) order, since the old value was readable from vault `cache`. |
| `CACHE_API_KEY/password` is also Kura's `KURA_ANALYTICS_SIGNING_KEY` | Kura gets its own keys (`kuraController.analytics.signingKeyItem`) | (1) Create an item (e.g. `KURA_ANALYTICS_SIGNING_KEY`) in each env's vault whose field `keys` is `<current CACHE_API_KEY>,<new key>` (`openssl rand -hex 32`). (2) Set `signingKeyItem` and deploy: Kura's key is unchanged, so Kura does not roll, and every server pod now accepts the new key. (3) Reorder `keys` to `<new key>,<current CACHE_API_KEY>` and force-sync; Kura rolls onto the new key. Kura signs when it sends, and Bazel invocations are posted without an outbox, so a server pod that did not hold the key would drop them: that is why step 2 comes first. (4) Once every Kura pod has rolled, drop the old value from `keys` and rotate `CACHE_API_KEY` (server and Kamal cache), since Kura nodes held it. |
| Atlas `GUARDIAN_SECRET_KEY` and `SECRET_KEY_BASE` both read `atlas-secret-key-base/password`; the Atlas ClickHouse password defaults to `SECRET_KEY_BASE` | `atlas-guardian-secret-key`, `atlas-clickhouse` | (1a) Map `GUARDIAN_SECRET_KEY_PREVIOUS` to `atlas-secret-key-base/password`, the value `GUARDIAN_SECRET_KEY` already reads, deploy: nothing changes. (1b) Create `atlas-guardian-secret-key` (`openssl rand -base64 64`), point `GUARDIAN_SECRET_KEY` at it, deploy. MCP tokens keep working; during the roll, tokens the new replica issues fail on the old one until it restarts. (1c) Remove the PREVIOUS mapping a day later. (2a) Create `atlas-clickhouse` holding a copy of the **current** `atlas-secret-key-base` value (copy it within 1Password only), map `ATLAS_CLICKHOUSE_PASSWORD` to it, set `clickhouse.passwordSecretKey: ATLAS_CLICKHOUSE_PASSWORD`, deploy: the password does not change, so nothing loses its connection. (2b) Rotate `atlas-clickhouse` later in a quiet window: change it, force-sync, then restart the ClickHouse StatefulSet and the Atlas Deployment by hand (`kubectl rollout restart`); the chart does not restart Atlas when the password changes, and queries fail until both have restarted. (3) Then rotate `atlas-secret-key-base`: signs everyone out and makes saved AI provider keys (`Atlas.Inference`, `MessageEncryptor` keyed by `SECRET_KEY_BASE`) unreadable until re-entered. |

## Inventory

Columns: **Where** is the source of truth; **Lands in** is the Kubernetes
Secret (namespace `<app>` is the Tuist release namespace); **Reload** is what it
takes for a rotated value to be used.

### Tier 1: roots of trust

| Credential | Where | Lands in / used by | Reload | Notes |
| --- | --- | --- | --- | --- |
| Per-env ESO service account token | 1Password `Founders`, referenced by item UUID (`bootstrap-workload.sh` step 9, `op://Founders/${OP_TOKEN_ID}/credential`) | `onepassword/onepassword-sa-token` in each workload cluster; read by ESO's `onepassword` ClusterSecretStore (vault `tuist-k8s-<env>`, [`k8s/mgmt/bootstrap/onepassword-secretstore.yaml`](k8s/mgmt/bootstrap/onepassword-secretstore.yaml)) | **Restart ESO**: its 1Password SDK client caches the token for the controller's lifetime | Same service account as the env's GitHub Environment `OP_SERVICE_ACCOUNT_TOKEN` ([`eso-token-refresh.yml`](../.github/workflows/eso-token-refresh.yml)), which also reads `kubeconfig: tuist-<env>`. Recovery workflow: **ESO Token Refresh**. |
| Mgmt ESO service account token (`tuist-mgmt-k8s`) | 1Password `Founders`, item `sfbjwcktutbhtilzjatwx3rkdy` | `onepassword/onepassword-sa-token` on the mgmt cluster; read-only on `tuist-k8s-mgmt` | Restart ESO on mgmt | Procedure in the header of [`k8s/mgmt/external-secrets.yaml`](k8s/mgmt/external-secrets.yaml). |
| GitHub Environment `OP_SERVICE_ACCOUNT_TOKEN` (`server-k8s-<env>`, `mgmt-hetzner`, others) | GitHub Environment secrets | Deploy and mgmt workflows (`op document get "kubeconfig: tuist-<env>"`, `op read`) | Next workflow run | Scope per token is **unverified** from the repo. |
| Repo-level `OP_SERVICE_ACCOUNT_TOKEN` | GitHub repository secret | Reads vault `tuist` (Cloudflare, Tuist Automation GitHub App) for docs, handbook, status and automation jobs | Next run | Signing and publish keys moved out to per-environment tokens; see [Release signing and publishing credentials](#release-signing-and-publishing-credentials). Until that rollout's step 6, the vault still holds them. |
| Release environment `RELEASE_OP_SERVICE_ACCOUNT_TOKEN` (`apple-signing`, `app-release`, `google-play`, `gradle-plugin-portal`) | GitHub Environment secrets | One read-only service account per environment | Next run | Rotate with 1Password's Rotate Token (sets an overlap), then `gh secret set RELEASE_OP_SERVICE_ACCOUNT_TOKEN --env <environment>`. |
| `CACHE_OP_SERVICE_ACCOUNT_TOKEN`, `ATLAS_OP_SERVICE_ACCOUNT_TOKEN` | GitHub repository secrets | Cache and Atlas deploy workflows (vaults `cache`, `atlas-k8s-production`) | Next run | |
| 1Password `Founders` vault | 1Password | Humans; bootstrap scripts read `tuist-workloads` (Hetzner), `cloudflare-tuist-dns`, `cloudflare-origin-cert-tuist-dev`, the ESO tokens | n/a | Root of trust for every env. A Founders compromise means rotating everything below. |
| GitHub org owners, Google Workspace admins, Tailscale admins, cloud-console users | Each provider | Humans | n/a | Reset passwords and sessions, re-enroll 2FA, review admins. Outside the repo. |

**Rotate a 1Password service account** (per env, starting with production):

1. In 1Password, create a new service account with the same vault access as the
   old one (check its vaults in the 1Password admin console first; the repo does
   not record them). Save its token to `Founders` as a new item.
2. ESO: re-stamp `onepassword/onepassword-sa-token` from the new token and
   restart ESO. For workload clusters the **ESO Token Refresh** workflow does
   both from the env's `OP_SERVICE_ACCOUNT_TOKEN`, so update that GitHub
   Environment secret first, then dispatch the workflow per env. Verify every
   `ExternalSecret` returns to `Ready=True`:
   `kubectl get externalsecret -A | grep -v True`.
3. Update every GitHub secret that held the old token (environment and
   repository level).
4. Delete the old service account in 1Password. That revokes it everywhere at
   once; anything still holding it fails with `bad credentials`, which is the
   check that nothing was missed.

The vault split and short-lived deploy credentials being designed in
[the deploy-credentials thread](https://ampcode.com/threads/T-01a1e431-0de8-70c5-9ee9-424e73991f95)
change this row: once ESO and CI no longer share a token, rotate them
separately. Update this section when that lands.

### Tier 2: cluster access and PKI

| Credential | Where | Lands in / used by | Reload | Notes |
| --- | --- | --- | --- | --- |
| Workload admin kubeconfig (`kubeconfig: tuist-<env>`) | 1Password document in `tuist-k8s-<env>`; CAPI copy `org-tuist/tuist-<env>-kubeconfig` on mgmt | Humans (break-glass), CI workflows via `op document get` | n/a | An x509 client certificate signed by the cluster CA. **It cannot be revoked**; it stays valid until it expires or the CA is replaced. CAPI renews its own copy; the 1Password copy is whatever was stored last. |
| CI deployer token (`github-actions-deployer-token`) | Long-lived ServiceAccount token Secret in each workload cluster ([`k8s/mgmt/ci-service-account.yaml`](k8s/mgmt/ci-service-account.yaml)); embedded in GitHub Environment secret `KUBECONFIG` (`server-k8s-<env>`) | Deploy workflows | Next run | Rotate: delete and recreate the token Secret (revokes immediately), re-mint the kubeconfig per [onboarding §5](k8s/onboarding.md#5-wire-the-github-actions-deployer), update the GitHub secret. Atlas has the same in [`k8s/atlas/ci-service-account.yaml`](k8s/atlas/ci-service-account.yaml). |
| CAPI workload CA, etcd CA, front-proxy CA, ServiceAccount signing key | Mgmt cluster `org-tuist/tuist-<env>-ca`, `-etcd`, `-proxy`, `-sa` (Cluster API kubeadm convention) | Every control-plane node; the SA key signs every ServiceAccount token | Control-plane roll (CA: every node) | See [Cluster CAs and ServiceAccount keys](#cluster-cas-and-serviceaccount-signing-keys). |
| Mgmt cluster Talos secrets bundle and `talosconfig: tuist-mgmt` | 1Password `Development` (talosconfig); machine configs on the nodes | Operators over the tailnet; `mgmt-talos` Jobs mint short-lived credentials | n/a | See [Management cluster](#management-cluster-talos). |
| Mgmt kubeconfig `kubeconfig: tuist-mgmt` | 1Password `tuist-k8s-mgmt` | Humans, mgmt workflows | n/a | Talos-issued admin certificate; same revocation limits. |
| `capi-workload-kubeconfig` | `tuist-k8s-<env>` → `<release>-capi-kubeconfig` / `<cluster>-kubeconfig` (Mac-mini fleets, [onboarding §5b](k8s/onboarding.md#5b-capi-workload-kubeconfig-mac-mini-fleets-only)) | CAPI Apple Silicon provider in the workload cluster | Restart provider | |
| `RACK_BORROWER_STAGING_KUBECONFIG`, `RACK_BORROWER_CANARY_KUBECONFIG` | `tuist-k8s-production` → `x-tuist-rack-borrower-*` (5 min refresh) | Production lending the rack hosts to staging/canary | Next reconcile | Credentials *into* staging and canary held by production. |
| tart-kubelet machine tokens | Per-machine ServiceAccount tokens (`tart-kubelet-<machine>`) issued by the provider during host bootstrap | Each Mac mini | Re-bootstrap host | Cluster-wide Secret read today; narrowed by [the tart-kubelet thread](https://ampcode.com/threads/T-01a1e431-1dad-7669-9318-bd7233803a97). Rotating the SA signing key invalidates them. |
| Pomerium (`POMERIUM_<ENV>`: shared secret, cookie secret, signing key, Google IdP client) | `tuist-k8s-<env>` → `pomerium/pomerium-tuist` | Pomerium + kube-impersonator | Restart Pomerium | Rotating cookie/shared secrets signs everyone out of kubectl. |
| Tailscale operator OAuth client (`TAILSCALE_OPERATOR`) | `tuist-k8s-<env>` → `operator-oauth` | Tailscale operator | Restart operator | Regenerate in the Tailscale admin console with the same tags. |
| Tailscale fleet keys (`TAILSCALE` auth key, `TAILSCALE_RACK_NODES`, `TAILSCALE_DEVICE_REAPER`) | `tuist-k8s-<env>` | CAPI providers (new hosts join with it), rack install sticks, device reaper | Restart provider / reaper | Existing devices keep their node keys; revoke suspicious devices in the admin console. See [onboarding §5c/§5d](k8s/onboarding.md#5c-tailscale-fleet-credential-mac-mini-fleets-only). |

### Tier 3: infrastructure API keys

| Credential | Where | Lands in / used by | Reload | Notes |
| --- | --- | --- | --- | --- |
| Hetzner Cloud token, workload projects | 1Password `Founders/tuist-workloads`; mgmt `org-tuist/hetzner` (also Robot credentials) | caph on mgmt; caph copies it to `kube-system/hcloud` in each workload cluster for HCCM and hcloud-csi; `reconciliation-checks`; `hetzner-robot-controller` | Restart caph, HCCM, hcloud-csi, robot controller | All tenants (`staging`, `canary`, `production`, `once`, `atlas`) reuse the one `org-tuist/hetzner` Secret. Rotate: create a new token in the Hetzner project, update the Founders item and `org-tuist/hetzner` (`hcloud` key, keep Robot keys), restart caph, confirm `kube-system/hcloud` updated per cluster, restart HCCM and hcloud-csi, revoke the old token. **Unverified:** whether caph re-copies an updated token into existing clusters; check `kube-system/hcloud` and patch it by hand if not. |
| Hetzner Cloud token, mgmt project | `tuist-k8s-mgmt-hetzner/hetzner-tuist-mgmt` | `mgmt-cluster-apply.yml` `hetzner` job (main-only `mgmt-hetzner` environment) | Next run | Replace in the Hetzner `tuist-mgmt` project, then 1Password. |
| Hetzner Robot credentials | `org-tuist/hetzner` (Robot keys) | caph bare-metal, `hetzner-robot-controller` | Restart both | Robot web-service user; rotate in Robot. |
| OVH API (`OVH_API`: application key/secret, consumer key) | `tuist-k8s-<env>` → `<release>-ovh` | CAPI provider (`<release>-capi-scaleway-applesilicon` Deployment), env vars | Restart provider | Mint a new consumer key with the same GET-only scopes; revoke the old one in the OVH API console. `baremetal:prep-ovh` also reads it (people only). |
| Vultr API (`VULTR_API`) | `tuist-k8s-<env>` → `<release>-vultr` | CAPI provider, env var | Restart provider | The new key's **source-IP allowlist starts empty**: add the stable-egress Floating IP before revoking the old key, or every call returns 401. |
| Scaleway IAM (`SCALEWAY_API`) | `tuist-k8s-<env>` → `<release>-capi-scaleway-applesilicon` | CAPI provider, env vars | Restart provider | |
| Cloudflare DNS token (cert-manager, external-dns) | 1Password `Founders/cloudflare-tuist-dns` → `platform/cloudflare-api-token`, created out-of-band by `install-platform.sh` | cert-manager DNS01, external-dns | Restart both | Not ESO-managed: replace the Secret by hand (`kubectl -n platform create secret generic cloudflare-api-token --from-literal=api-token=... --dry-run=client -o yaml \| kubectl apply -f -`). |
| Cloudflare operator token | mgmt `tuist-k8s-mgmt` item `cloudflare-operator` → `cloudflare-operator/cloudflare-operator-token` | Cloudflare operator on mgmt (WAF/bot rules) | Restart operator | |
| Cloudflare deploy tokens | Vault `tuist` item `Cloudflare`; `atlas-k8s-production/cloudflare-inbox-worker` | `wrangler` deploys in CI | Next run | |
| Cloudflare origin certificate | `Founders/cloudflare-origin-cert-tuist-dev` | Ingress default certificate set up by `bootstrap-workload.sh` | Ingress reload | Revoke and re-issue in Cloudflare if the key leaked. |
| AWS Route53 (cache DNS) | `tuist-k8s-<env>` item `cache-dns-controller` → `kura/kura-cache-dns`; platform `cacheDNS` credentials | Kura controller, cert-manager/external-dns for `cache.tuist.dev` | Restart | Separate identities by design; see [`cache-dns/README.md`](cache-dns/README.md). |
| Tigris/S3 workload keys (`S3_CREDENTIALS`, `REGISTRY` S3 fields) | `tuist-k8s-<env>` → `<release>-object-storage-external-secrets`, `<release>-registry-runtime`, `<release>-swift-registry-sync-external-secrets` | Server, processor, registry, swift-registry-sync | Restart all of them | Create the new key in Tigris before revoking the old one. |
| Luft Git Tigris key (`LUFT_GIT_S3`, fields `access_key_id`, `secret_access_key`) | `tuist-k8s-production` → `luft/luft-git-s3` via the standalone Git chart's optional ExternalSecret | StatefulSet `luft-git`, env vars | Sync ESO, restart StatefulSet, verify API round trip, then revoke old key | Dedicated read/write key for `luft-git-production` only; default organization permissions disabled. See [`helm/luft-git/README.md`](helm/luft-git/README.md#provision-before-installation). Never reuse Tuist's key. |
| Tigris backup keys (`S3_BACKUP_CREDENTIALS`, `atlas-*-backup`) | per vault | Server CNPG/barman, ClickHouse backup | CNPG picks up on reconcile; verify the next WAL archive | Scoped to the backup buckets only ([`cnpg/README.md`](cnpg/README.md#backup-configuration)), not to prefixes. |
| Per-app backup keys (`SYMPTOMS_PG_BACKUP`, `TUIST_OPS_PG_BACKUP`, `MDM_PG_BACKUP`) | `tuist-k8s-<env>` → `<app>-backup-credentials` | Symptoms, tuist-ops, MDM CNPG/barman | CNPG picks up on reconcile; verify the next WAL archive | Each its own Tigris key, policy limited to `tuist-<env>-pg-backups/<app>/*` ([`helm/symptoms/README.md`](helm/symptoms/README.md#backup-key)). The charts refuse `S3_BACKUP_CREDENTIALS`. |
| Pulse S3 (`PULSE_S3_CREDENTIALS`) | `tuist-k8s-<env>` | Pulse | Restart Pulse | |
| Grafana Cloud tokens (`PROMETHEUS_TOKEN`, `LOKI_TOKEN`, `TEMPO_TOKEN`) | `tuist-k8s-<env>` / `tuist-k8s-mgmt` → `observability/k8s-monitoring-grafana-cloud` | Alloy collectors | Restart Alloy | Create the new access-policy token in Grafana Cloud first; logs are evidence, so do not leave a gap during an incident. |
| `PDC_AGENT` | `tuist-k8s-<env>` → `<release>-pdc-agent` | Grafana private datasource connect agent | Restart | |
| Docker Hub (`DOCKER_HUB_CREDENTIALS`) | `tuist-k8s-<env>` → `<release>-registry-cache-upstream` | Registry pull-through cache | Restart | |
| Fleet SSH keys (`OVH_FLEET_SSH`, `VULTR_FLEET_SSH`, `BER1_FLEET_SSH`) | `tuist-k8s-<env>` → `<release>-<provider>-fleet-<fleet>-ssh` | CAPI provider SSH into hosts | Restart provider **and** install the new public key on every host first | Hosts trust the public key, so this is a two-phase change: add the new key to `authorized_keys` everywhere, switch the item, restart, then remove the old key. |
| Mac mini fleet SSH key | Generated by `mise run k8s:prepare-fleet-ssh-key` | CAPI Apple Silicon provider | As above | |
| BER1 rack: `BER1_RACK_CARD_ROOT`, `AMT_PROVISIONING_CERT`, switch admin/Omada credentials | `tuist-k8s-production` | Rack controllers, `rack-switch-controller` | Restart | Switch logins are pushed by `rack:fleet`; see [`rack-switch-fleet/AGENTS.md`](rack-switch-fleet/AGENTS.md). |

### Tier 4: server root keys

All in item `SECRET_KEYS` (vault `tuist-k8s-<env>`), synced into
`<release>-server-config-external-secrets` and read through `envFrom` by the
server, the migration Job, the processor and the xcresult processor
([`helm/tuist/templates/server-config-external-secrets.yaml`](helm/tuist/templates/server-config-external-secrets.yaml)).
**Every one needs a restart of all of those**, and a rolling restart mixes old
and new pods for a few minutes. `MASTER_KEY` and the encrypted
`priv/secrets/<env>.yml.enc` blob are no longer used by the managed
environments (`values-managed-common.yaml`); there is nothing to rotate there.

| Field | Env var | Protects | Effect of rotating | Rotatable today? |
| --- | --- | --- | --- | --- |
| `base` | `TUIST_SECRET_KEY_BASE` | Phoenix `secret_key_base`: session cookies, signed and encrypted cookies, LiveView tokens; dev fallbacks of the keys below | Signs everyone out of the dashboard, and invalidates every `Phoenix.Token`: queued account-artifact and archive-copy deletion jobs, runner job report tokens (12 h), queued confirmation emails, preview install and build-trace links, GitHub/Slack connections in progress | Yes, after draining the `DeleteAccountArtifactsWorker` and archive-copy deletion queues. Generate with `openssl rand -base64 64`. Hosted production and canary refuse to boot when `password` or `tokens` is unset, blank or equal to `base`, or the two are equal (`Tuist.Environment.validate_secret_keys!/2`); [split them first](#splitting-reused-secrets). |
| `tokens` and `tokens_previous` | `TUIST_SECRET_KEY_TOKENS`, `TUIST_SECRET_KEY_TOKENS_PREVIOUS` (when `server.config.previousTokensKey.enabled`) | `Tuist.Guardian` JWT signing (sessions, CLI and OAuth access/refresh tokens, account tokens). Tokens carry a `kid`; `tokens_previous` only verifies (`Tuist.Guardian.SecretFetcher`). While `cacheTokenKey.signing` is off, also cache tokens, which the Kamal cache verifies with `GUARDIAN_SECRET_KEY` (vault `cache`) | Without `tokens_previous`, every issued token stops verifying. Two other consumers derive from `tokens` and ignore `tokens_previous`: sandbox command credentials (`Tuist.Sandboxes.CommandCredentials`, 7 h) stop verifying, and the P-256 keys derived by `Tuist.Accounts.AgentAuthSigningKey` (auth.md assertions, Anthropic federation and Claude linked-billing JWTs, each published through a JWKS) change at once | **Yes, without logging anyone out** (running sandbox commands may need a retry; Anthropic and auth.md verifiers must refetch the JWKS, so in-flight assertions fail once): (a) copy `tokens` into `tokens_previous`, enable `previousTokensKey`, deploy: nothing changes, because the previous key equals the current one. (b) Immediately before a deploy, set a new `tokens` (`openssl rand -base64 64`), force-sync the server config ExternalSecret, deploy. During that rolling restart, tokens issued by new pods fail on old pods until the rollout ends; clients retry or log in again. Never change `tokens` without `tokens_previous` already synced: the ExternalSecret refreshes hourly, and a pod that starts with the new key and no previous key rejects every live token. (c) After 30 days, clear the field, disable the flag, deploy. If the old key leaked, skip `tokens_previous` and accept the hard cut. Do it only after the Kamal cache verifies with `CACHE_TOKEN_PUBLIC_KEY` and `GUARDIAN_SECRET_KEY` is gone from vault `cache` (see [Cache](#splitting-reused-secrets)), or the cache's fast path breaks. |
| `cache_tokens` | `TUIST_SECRET_KEY_CACHE_TOKENS` (when `server.config.cacheTokenKey.enabled`) | ES256 keypair for cache tokens (`Tuist.CacheGuardian`) | Outstanding cache tokens fail; Kura re-exchanges | Yes. Keep `cache_token.signing_enabled` semantics in mind: install the key everywhere before switching issuance (see `Tuist.Environment.cache_token_signing_enabled?/1`). |
| `password` | `TUIST_SECRET_KEY_PASSWORD` | **Pepper** appended before bcrypt for user passwords, project tokens, Kura self-hosted client secrets, and the HMAC key of the authentication subject cache | **Every user password and every hashed project token and Kura client secret stops matching.** | **No.** Rotating it is a mass credential reset: users reset passwords, customers re-issue project tokens. Only do it with a customer notice. A pepper leak alone does not expose passwords (they are still bcrypt), so it is rarely worth it. |
| `encryption` (legacy key `V1`) and `encryption_keys` | `TUIST_SECRET_KEY_ENCRYPTION`, `TUIST_SECRET_KEY_ENCRYPTION_KEYS`; `TUIST_SECRET_KEY_ENCRYPTION_CURRENT_KEY` from the Helm value `server.config.encryptionKeys.currentKeyId` | Cloak AES-GCM keys for every encrypted DB column (GitHub/GitLab/Bitrise/Buildkite tokens, customer S3 keys, OAuth client secrets, Slack tokens, MFA secrets, runner payloads). `encryption_keys` is a ring of comma-separated `id:base64` entries (32-byte keys, `openssl rand -base64 32`, id not `V1`); `encryption` stays readable as key `V1`. Values carry their key id in the tag `AES.GCM.<id>` | Removing a key that values are still encrypted under makes those values unreadable | **Yes, in three deploys.** Follow the runbook in the `Tuist.Vault` moduledoc (`server/lib/tuist/vault.ex`): (1) add the new key to `encryption_keys` (`server.config.encryptionKeys.enabled: true` the first time) with `currentKeyId` pinned to the key in use, deploy; (2) set `currentKeyId` to the new id, deploy; (3) run `bin/tuist eval 'Tuist.Release.reencrypt_vault("<id>")'` until it passes, let Oban jobs queued before step 2 drain, remove the old key (`legacyKey: false` for `V1`), deploy. If the old key is compromised, ship steps 1 and 2 together and accept read failures on old pods during that rollout. Hosted production and canary refuse to boot when no key is configured, when the current key is `V1` and shorter than 32 bytes, or when the current key is derived from `SECRET_KEYS/base`; staging still falls back to `base`. |

Other server keys:

| Credential | Where → Secret | Reload | Notes |
| --- | --- | --- | --- |
| `KURA_VOLUME_ROOT_KEYS`, `KURA_VOLUME_TRANSPORT_KEYS` | `tuist-k8s-<env>` → server config Secret | Server restart; CSI node plugins pin the transport public key | Versioned, newest first; follow [`kura-volumes-csi/security/key-management.md`](kura-volumes-csi/security/key-management.md#rewrap-retirement-and-recovery). |
| `TUIST_CACHE_GRANT_PRIVATE_KEY`, `TUIST_LICENSE_CERTIFICATE_BASE64` | `tuist-k8s-<env>` → `<release>-server-external-secrets` | Server restart | The license certificate is issued by Tuist; re-issue only if the signing side leaked. |
| `CACHE_API_KEY` | → server config Secret; `kura/kura-shared-secrets` as `KURA_ANALYTICS_SIGNING_KEY` until `kuraController.analytics.signingKeyItem` is set | Restart server **and** Kura | The Kamal cache's webhook signing key. Kura signed with it too; give Kura its own key first ([split](#splitting-reused-secrets)), then this rotates without touching Kura. |
| Kura analytics signing keys (`<kuraController.analytics.signingKeyItem>/keys`, item to be created, e.g. `KURA_ANALYTICS_SIGNING_KEY`) | → server config Secret (`TUIST_KURA_ANALYTICS_SIGNING_KEYS`, all of them) and `kura/kura-analytics` (first one) | Server restart, then Kura rolls on the Secret change | Comma-separated, Kura signs with the first. Rotate: append the new key, deploy the server (every pod must hold it before Kura signs with it); move it to the front and force-sync (Kura rolls); drop the old one once every Kura pod has rolled. |
| `OIDC_PROVIDER/signing-key.pem` | `tuist-k8s-production` → server config Secret (`TUIST_OIDC_SIGNING_KEY`, when `luftServerOidc.enabled`) | Server restart; luft-server refetches `/oauth2/jwks` | Signs the ID tokens Tuist issues to luft-server (RS256, `kid` derived from the key). The file may hold several PEM blocks: the first signs, `/oauth2/jwks` publishes all. Rotate: append the new key after the current one with `cat current.pem new.pem` (no blank line, LF endings: the `kid` is an MD5 of the exact PEM text, so any whitespace change to the current block changes its `kid`), deploy; an hour later (luft-server's JWKS cache) move it first, deploy; drop the old block once ID tokens signed with it have expired (`id_token_ttl` is one hour). Generate with `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048`. |
| `LUFT_SERVER` (`oauth_client_id`, `oauth_client_secret`) | `tuist-k8s-production` → server config Secret (`TUIST_LUFT_SERVER_OAUTH_*`) and `luft-server` runtime Secret | Restart server **and** luft-server | One client secret held by both sides; the server seeds it into its OAuth client. A rotation is a coordinated switch: users who start a login during it retry. `secret_key_base` in the same item is luft-server's own, see [Tier 5](#tier-5-databases-storage-and-internal-apps). |
| `kura-introspection-oauth-client` | → `<release>-server-external-secrets`, `kura/kura-shared-secrets` | Restart server and Kura | |
| `SERVER_CLUSTER_COOKIE` | → `tuist-server-cluster-cookie` (`OnChange`) | Coordinated replacement of every web pod | [onboarding §5e](k8s/onboarding.md#5e-durable-server-distribution-cookies). |

### Tier 5: databases, storage and internal apps

| Credential | Where → Secret | Reload | Notes |
| --- | --- | --- | --- |
| Postgres roles (`WEB_DATABASE_PASSWORD`, `PROCESSOR_DATABASE_PASSWORD`, `OPS_DATABASE_PASSWORD`, `GRAFANA_DATABASE_PASSWORD`, `SWIFT_REGISTRY_SYNC_DATABASE_PASSWORD`) | `tuist-k8s-<env>` → `<release>-pg-<role>` | CNPG runs `ALTER ROLE` on reconcile; then restart the role's clients | [`cnpg/README.md` → Password rotation](cnpg/README.md#password-rotation). The superuser and replication certificates are CNPG-generated; rotate by deleting the CNPG-managed Secret (CNPG regenerates it) if the cluster is suspected. |
| ClickHouse users (app, `CLICKHOUSE_GRAFANA`, ops) | `tuist-k8s-<env>`; managed ClickHouse renders users from values | Restart server/processor; ClickHouse pods roll on the config checksum | Restricted identity: [`clickhouse/README.md`](clickhouse/README.md). |
| Redis | In-cluster, no external credential | n/a | |
| tuist-ops (`TUIST_OPS_BOT`, synced whole: the JIT bot's Slack credentials and `secret_key_base`; its CNPG cluster and backup key) | `tuist-k8s-production` → tuist-ops Secrets | Restart tuist-ops | Rotate Slack credentials in the Slack app config first. tuist-ops serves the impersonation policy for every env, so restart it in a quiet window. |
| Atlas core (`atlas-secret-key-base`, `atlas-encryption-key`, `atlas-github-app`, `atlas-google-oauth`, `atlas-slack-company`, `atlas-stripe-api-key`, `atlas-mercury`, `atlas-qonto`, `atlas-apns`, `atlas-license-signing-key`, `atlas-super-admin`, …) | `atlas-k8s-production` → `atlas-app` (`refreshInterval: 1h`); also the ClickHouse StatefulSet and backup CronJob | Restart Atlas (and ClickHouse while it reads `SECRET_KEY_BASE`) | Atlas holds bank and finance API credentials and the license signing key: treat them as Tier 4. `atlas-encryption-key` (`ENCRYPTION_KEY`, key `V1`) rotates through a key ring like the server's: add `ENCRYPTION_KEYS` (`atlas-encryption-keys/password`, `<id>:<base64 32-byte key>`) and `ENCRYPTION_KEY_IDS: "V1,<id>"` with `ENCRYPTION_CURRENT_KEY: "V1"` in `env:`, deploy; set `ENCRYPTION_CURRENT_KEY` to the new id, deploy; run `bin/atlas eval 'Atlas.Release.reencrypt_vault("<id>")'` until it exits zero; drop `ENCRYPTION_KEY` and `V1` from `ENCRYPTION_KEY_IDS`, deploy (`Atlas.Vault` moduledoc). `GUARDIAN_SECRET_KEY` rotates with `GUARDIAN_SECRET_KEY_PREVIOUS` (one-day overlap). Both still read `atlas-secret-key-base` today: [split it](#splitting-reused-secrets). |
| `atlas-ghcr-pull/notesPlain` | → `ghcr-pull` (dockerconfigjson), `imagePullSecrets` | Next image pull | GitHub PAT: create a new one, update, sync, revoke the old one. Prefer a GitHub App or a fine-grained read-packages token. |
| `atlas-object-storage` | → `atlas-app` and the vector Deployment's `<vector>-storage` | Restart Atlas and vector | Hetzner Object Storage key. |
| `atlas-postgres-backup`, `atlas-clickhouse-backup` | → `atlas-postgres-backup-credentials` (CNPG barman), `atlas-clickhouse-backup-credentials` | CNPG on the next backup (verify a WAL archive); the CronJob's next run | Hetzner Object Storage keys. |
| `atlas-inbox-webhook-secret/password` | → `atlas-app`; also the Cloudflare Worker `atlas/workers/inbox` (`wrangler secret put`) | Restart Atlas and redeploy the Worker together | Shared HMAC: hard cut, mail in between is rejected ([`k8s/atlas/onboarding.md`](k8s/atlas/onboarding.md)). |
| `atlas-gtm-ingest-token/password` | → `atlas-app` | Restart Atlas | Bearer token for the Loops-compatible ingest endpoints. Hard cut; its callers are not recorded, find them first. |
| `atlas-pulse-sentry/password` | → `atlas-app` | Restart Atlas | Tuist account token (`account:pulse:write`) on production: new token, restart, revoke the old one. |
| `atlas-ses` | → `atlas-app` | Restart Atlas | AWS IAM key: two keys allow an overlap. |
| `atlas-hive-inference-token`, `atlas-hive-embedding-token`, `atlas-granola-api-key`, `atlas-qonto-oauth`, `atlas-mailgun`, `atlas-brave-search-api-key`, `atlas-apollo-api-key`, `atlas-pingen` | → `atlas-app` | Restart Atlas | Rotate at each issuer, update, restart. Saved AI provider keys entered in the app are encrypted under `SECRET_KEY_BASE`, not these. |
| `atlas-slack-agent-identities`, `atlas-slack-agent-channel-policies`, `atlas-chatgpt-oauth/client_id`, `atlas-tuist-gmbh/*` | → `atlas-app` | n/a | Not credentials: the first two are synced but unread (remove them), the client ID is public, `atlas-tuist-gmbh` is company data. |
| MDM (`MDM` item: NanoMDM and NanoDEP API keys, webhook HMAC key, SCEP CA key, Apple assets) | `tuist-k8s-production` → `<release>-mdm-runtime`, `-scep-ca`, `-assets` | Restart MDM | API and HMAC keys rotate freely. Apple push and DEP material is renewed through Apple's portals ([`mdm/`](mdm/AGENTS.md)). Rotating the SCEP CA re-enrolls every Mac. |
| Slack invite app (`SLACK_INVITATION_APP`) | → `slack-runtime` | Restart | |
| Typesense (`TYPESENSE_API_KEY`, `SEARCH_GITHUB_TOKEN`) | → `typesense-runtime` | Restart Typesense and indexers | |
| `PULSE_TOKEN/password` (all envs and mgmt) | → `observability/pulse-dashboard-auth` (`dashboard:ro` and `tuist:wo` share it), server `TUIST_PULSE_TOKEN` (production, staging), staging `pulse-grafana-staging` | Restart the Pulse frontends, then server and processors and pulse-grafana; Alloy reads it through the API | Hard cut: Pulse loads static users at startup. No `=` or newlines in the value. One password for a read user and a write user; give each its own field when next rotated. The symptoms evaluator does not hold it. |
| `PULSE_SYMPTOMS_READER/password` (envs in the pulse chart's `symptomsReader.environments`) | → `pulse-dashboard-auth` (`symptoms:ro`), `symptoms-<env>/symptoms-runtime` | Restart the Pulse frontends, then symptoms | Hard cut. Letters and digits only. Read-only. |
| `PULSE_SENTRY_WRITER/password` | → `pulse-dashboard-auth` (`sentry:wo`), server `TUIST_SENTRY_PULSE_DSN`, `tuist-tuist-registry-runtime`, `kura/kura-sentry-pulse-secrets` | Restart Pulse frontends, server and processors, registry; Kura rolls on the Secret change | Hard cut; only error reports are lost in between. Letters and digits only. |
| `PULSE_SENTRY_XCRESULT/token` (production, staging) | → server config Secret as `TUIST_SENTRY_PULSE_PUBLIC_DSN` | Restart `xcresult-processor` (Tart VMs) | A Tuist account token on the `tuist` account (`account:pulse:write`). Overlap: create a new token on that env's server, update, sync, restart, revoke the old one. |
| `PULSE_S3_CREDENTIALS` (all envs and mgmt) | → `observability/pulse-credentials` | Rolling restart of `pulse-datanode` (standalone Pulse on mgmt) | Tigris key. Overlap: create a key, update, restart, revoke the old one. Staging also has an ExternalSecret `pulse-storage-44877167204-2` on this item that is not in the repository: find its owner before revoking. |
| symptoms | No 1Password item of its own: API calls are authenticated with the server's ServiceAccount (TokenReview); Pulse reads use `PULSE_SYMPTOMS_READER` above; backups use `SYMPTOMS_PG_BACKUP` | | |
| luft-server (`LUFT_SERVER/secret_key_base`; `LUFT_SERVER_CLUSTER_COOKIE/password`) | `tuist-k8s-production` → `luft/luft-server-runtime`, `luft/luft-server-cluster-cookie` (`OnChange`) | Replace both replicas at once | **`secret_key_base` is not rotatable without data loss:** keys derived from it encrypt stored Tuist tokens, thread checkpoints and tool results, push tokens and session journals, with no re-encryption tool. Rotating it signs everyone out and leaves their Tuist refresh tokens live for 30 days (luft-server cannot decrypt them to revoke), so revoke those on the Tuist server. The cookie is a hard cut ([`luft-server/README.md`](helm/luft-server/README.md)). The OAuth client fields are in [Tier 4](#tier-4-server-root-keys). |
| Shard storage, Garage (canary; staging by hand; production retired) | Generated in-cluster (`kura/shard-storage`, `CreatedOnce`), not in 1Password; access keys copied to `tuist-canary/shard-storage-targets` | Restart the store, its lifecycle CronJob and the server | `GARAGE_ADMIN_TOKEN` **is** the `rpc-secret`. Rotate: delete the Secret so the generator makes a new seed (the S3 keys change too), restart all of the above; revoke old S3 keys with Garage's key commands. Staging's Secret has no known source. |
| Shard storage, RustFS (production) | Generated in-cluster: `rustfs-production/rustfs-root`, `rustfs-service`, `rustfs-docker-mirror-service`; staging `RUSTFS_STAGING_ROOT` (no workload) | Restart every RustFS member and `rustfs-setup` | The server holds only the service user (`tuist/rustfs-targets`), never root. **Unverified:** whether RustFS accepts new root credentials without re-initialising IAM; rehearse on a scratch install first. |
| OpenObserve `root-password`, `internal-token` (staging, canary) | Generated once by CI into `openobserve-auth`, not in 1Password | Restart all pods at once | Not deployed live. The internal token is shared by every node (hard cut); the root password is probably applied only at first boot (users live in the metadata DB). Unverified. |
| Managed ClickHouse `interserver-password` | Helm-generated, kept in `<release>-clickhouse-credentials` | Replicas roll one at a time on the checksum | Rotate: delete only that key from the Secret (deleting the Secret also regenerates `password`), deploy. Hard cut: part fetches and `clusterAllReplicas` between old and new replicas fail during the roll. |
| `ops-slack-webhook-url` | `kuraRuntime.rollout.opsSlackWebhookSecret` (unset in every env) | Server restart | Not in use. If enabled: new incoming webhook, update, restart, delete the old webhook. |
| `TUIST_LICENSE_KEY` (Keygen) | `tuist-k8s-preview`, `tuist-k8s-pentest` → `server-license-key` | Server restart | Not used in managed envs (they use `TUIST_LICENSE_CERTIFICATE_BASE64`). Re-issue in Keygen. The pentest vault looks retired; delete it rather than rotate. `docsearch-forum` is a ConfigMap, not a credential. |
| `kura-sentry-atlas` | → `kura/kura-shared-secrets` | Restart Kura | DSN, low value. |

### Tier 6: third-party integrations

All synced into the server config Secret unless noted. Rotate at the issuer,
update the item, force-sync, restart the server, migration Job and processors,
then revoke the old value.

| Item | Fields | Issuer | Notes |
| --- | --- | --- | --- |
| `GITHUB_APP` | app_id, client_id, client_secret, webhook_secret, `private-key.pem` | GitHub App settings (Tuist GitHub App) | Separate Secret `<release>-github-external-secrets`. GitHub allows two private keys at once: generate the new key, deploy, then delete the old one. The webhook secret is a hard cut. Key rotation and permission review: [GitHub App thread](https://ampcode.com/threads/T-01a1e430-e75d-72d2-b718-9c50ba61d9c3). |
| `BUILDERS_FLEET_GITHUB_APP` | app-id, installation-id, private-key | GitHub App | VM image builder runners. |
| `FLUX_GITHUB_APP` (mgmt) | app_id, installation_id, `private-key.pem` | GitHub App | `flux-system/flux-system`; Flux reconnects on the next fetch. |
| Tuist Automation GitHub App | vault `tuist` (app-id, private-key) | GitHub App | CI release and deploy jobs on main; see [GitHub tokens in CI](#github-tokens-in-ci). |
| Tuist CI GitHub App | repository variable `TUIST_CI_APP_CLIENT_ID`, secret `TUIST_CI_APP_PRIVATE_KEY` | GitHub App | Read-only, reachable from pull requests; see [GitHub tokens in CI](#github-tokens-in-ci). |
| `GITHUB_TOKEN_UPDATE_PACKAGE_RELEASES` | PAT | GitHub | Stays for now; see [PATs that remain](#pats-that-remain). |
| `REGISTRY/REGISTRY_GITHUB_TOKEN` | PAT | GitHub | Fallback for the registry mirror; see [PATs that remain](#pats-that-remain). |
| `GITHUB_TOKEN_UPDATE_PACKAGES` | PAT | GitHub | Unused: nothing read it, and the chart no longer syncs it. Revoke it and delete the item once that chart is deployed everywhere. |
| `ORIGIN_APP` | app_id, private_key (Ed25519) | Tuist-registered app | Per env. |
| `OAUTH` | client_id, client_secret, `jwt-public-key.pem` | Tuist OAuth/OIDC | |
| `GOOGLE_OAUTH` | client_id, client_secret | Google Cloud console | `<release>-google-external-secrets`. |
| `APPLE` | client ids, team_id, private_key_id, `private-key.pem` | Apple Developer | Sign in with Apple. |
| `APNS`, `FCM` | p8 key, service-account.json | Apple, Firebase | Push notifications. |
| `STRIPE` | secret_key, publishable_key, endpoint_secret | Stripe dashboard (roll key; webhook secret per endpoint) | Stripe supports an expiry overlap when rolling. |
| `SLACK` | client_id, client_secret, tuist_token | Slack app | Customer workspace tokens are stored encrypted in the DB; see the [Slack thread](https://ampcode.com/threads/T-01a1e430-b6b0-71db-95ef-7100b9449d0d). |
| `SES`, `MAILGUN`, `ATLAS_EMAIL` | keys | AWS IAM, Mailgun | SES: [onboarding → Managed outbound email](k8s/onboarding.md#managed-outbound-email-ses). |
| `ENTIRE_PLUGIN`, `CHATGPT_OAUTH`, `TURNSTILE`, `SENTRY` | | Each issuer | `CHATGPT_OAUTH` is a public client ID. |

### Tier 7: customer-facing credentials

These belong to customers or are held for them. Rotating them is a customer
action, so the platform's job is to revoke and tell them.

- **Legacy user and project tokens** are stored in plaintext and survive every
  key rotation above. Hashing or retiring them, plus bulk revoke and notice
  tooling: [legacy tokens thread](https://ampcode.com/threads/T-01a1e431-0342-75a4-aad7-8fa520029c65).
- **Customer secrets stored encrypted in Tuist** (CI provider tokens, S3 keys,
  SSO client secrets, Slack tokens, runner payloads): readable by anyone holding
  the server's encryption keys (`SECRET_KEYS/encryption`,
  `SECRET_KEYS/encryption_keys`) and a database copy. Rotating those keys
  protects future copies only; ask customers to rotate the secrets at their
  source. Per-integration work: [S3 role federation](https://ampcode.com/threads/T-01a1e430-a045-76dd-bebb-5fb3ecdf3691),
  [SSO private_key_jwt](https://ampcode.com/threads/T-01a1e430-aa83-70da-99b0-9de4196fbb0b),
  [GitLab/Buildkite/Bitrise](https://ampcode.com/threads/T-01a1e430-c206-71ab-9ea7-b6c39efb067c),
  [runner payloads](https://ampcode.com/threads/T-01a1e430-d7e8-76a7-af89-99058a9de09f).
- **Tuist-issued account, project and SCIM tokens** are bcrypt-hashed with the
  `password` pepper: revoke individually in the product, or rotate the pepper
  as a mass reset (see Tier 4).

### CI and GitHub repository secrets

Referenced by `.github/workflows` (count of references): `OP_SERVICE_ACCOUNT_TOKEN`
(62), `TUIST_CI_APP_PRIVATE_KEY` (12), `KUBECONFIG` (5),
`HEX_API_KEY` (being retired), `CACHE_OP_SERVICE_ACCOUNT_TOKEN` (4), `CACHE_SSH_PRIVATE_KEY`,
`CACHE_KAMAL_SECRETS`, `ATLAS_OP_SERVICE_ACCOUNT_TOKEN`,
`COMMUNITY_SLACK_WEBHOOK_URL`, `PENTEST_USER_*`, `SPEC95_STAGING_CACHE_TOKEN`,
`AMP_ORB_ISOLATED_VALIDATION_TOKEN`, and per release environment
`RELEASE_OP_SERVICE_ACCOUNT_TOKEN`. Signing and publishing credentials have
their own section below.

Rotate each at its issuer and with `gh secret set` (repository or
`--env <environment>`). Workflow hardening (token scope, pinning, guards) is in
[the CI thread](https://ampcode.com/threads/T-01a1e431-33d5-71a0-9548-f69639c2c9bb).

### Release signing and publishing credentials

These sign or publish what customers install: the CLI, the macOS and iOS
apps, the Android app, Luft previews, the Gradle plugin and the Hex packages.
Someone holding one of them can ship code that customers' machines trust as
Tuist's, so treat them as Tier 4. They live outside the clusters, so the
ESO path above does not apply: each one is read by a CI job at release time,
and the procedures below replace it at its issuer.

**Where they live.** Each credential has its own 1Password vault, and each
GitHub environment has its own read-only 1Password service account. The
service account's token is that environment's `RELEASE_OP_SERVICE_ACCOUNT_TOKEN`.
No repository-level secret has that name, so a job outside the environment
gets an empty value instead of falling back to a broader token. Every one of
these environments must allow deployments from `main` only. On a pull request
or a pushed branch, the jobs that sign run without an environment.

| Environment | 1Password service account reads | Jobs |
| --- | --- | --- |
| `apple-signing` | `tuist-apple-signing` | `cli-build-publish.yml` `release-cli` (CLI and backports), `app-release.yml` `release-ios`, `app.yml` `app-device-build` (main only), `luft.yml` `apple` (signed legs on main only) |
| `app-release` | `tuist-apple-signing`, `tuist-sparkle` | `app-release.yml` `release-app` (macOS app, appcast) |
| `google-play` | `tuist-google-play` | `app-release.yml` `release-android` |
| `gradle-plugin-portal` | `tuist-gradle-plugin-portal` | `gradle-release.yml` `release` |
| `hex-publish` | none (Hex Workload Identity) | `publish` in `condukt-release.yml`, `noora-release.yml`, `tuist-ex-release.yml` |

1Password service accounts cannot gain or lose vault access after creation,
so changing what an environment reads means creating a new service account.
`app-release` reads two vaults because one job builds the DMG and signs the
appcast. Splitting the appcast into its own job and environment would mean
no single token holds both of the anchors Sparkle trusts (see below).

**Expiry.** The repository records no expiry date for any of these. The Luft
iOS bundle script refuses an expired ad-hoc profile at build time, and that
is the only check. Record the dates here after reading them in the Apple
Developer portal (Certificates, Profiles) and Google Play Console. Validity
periods set by the issuers:

| Credential | Validity | Expires |
| --- | --- | --- |
| Developer ID Application certificate (`tuist-apple-signing`, and the separate copy in vault `swifterpm`) | 5 years from creation | _record_ |
| Apple Distribution certificate | 1 year | _record_ |
| Ad-hoc and App Store provisioning profiles (Tuist App, Tuist Code, Tuist Code Live Activity) | 1 year, or less if the certificate expires sooner | _record_ |
| App Store Connect API key | No expiry; revoke to end it | n/a |
| Sparkle EdDSA key | No expiry | n/a |
| Google Play upload key | Validity of the keystore's certificate | _record_ |
| Google Cloud service-account key (Play publishing) | No expiry unless an org policy sets one | _record_ |
| Gradle Plugin Portal key and secret | No expiry | n/a |
| 1Password service-account tokens (`RELEASE_OP_SERVICE_ACCOUNT_TOKEN`) | None. 1Password caps `--expires-in` at 90 days, and an expired token fails the next release with no warning, so these were created without one. Rotate them once a year and after any suspected leak | n/a |

A person with the portal open can read a certificate's date from the portal
list. To read one from the 1Password copy without printing the key, read the
`.p12` to a file and run
`openssl pkcs12 -in certificate.p12 -nokeys -legacy | openssl x509 -noout -enddate -subject`.
Do this on a laptop, not in CI or an agent thread.

#### Developer ID Application certificate

Signs and, with notarization, makes Gatekeeper accept the CLI (`mise/tasks/cli/bundle.sh`),
the macOS app (`mise/tasks/app/bundle.sh`), Luft for macOS
(`luft/macos/distribution/bundle.sh`) and SwifterPM (`swifterpm/mise/tasks/release/package.sh`,
vault `swifterpm`). A leak lets someone sign software as "Tuist GmbH (U6LC622NKF)".
They would also need a notarization credential to get it past Gatekeeper on a
default Mac.

- **Rotate** (Account Holder; up to five Developer ID Application certificates
  can exist at once): create a new certificate from a CSR made on a trusted
  Mac, export it with its key as `.p12`, and replace the `certificate.p12`
  and `password` fields in `tuist-apple-signing` (and `swifterpm` if it is the
  same certificate). The next release signs with it. Nothing else changes:
  the scripts select the identity by name, and Sparkle accepts an update
  signed with a new certificate as long as the EdDSA key stays the same.
- **Revoke** (leak): email `product-security@apple.com` to ask Apple to
  revoke it. **Once it is revoked, every installed copy signed with it stops
  launching**, which includes every CLI, macOS app and SwifterPM release
  since the certificate was created. So rotate first, ship re-signed releases
  of each product, tell customers to update, then revoke. If the key is being
  used to sign malware, revoke at once and accept the outage.

#### Apple Distribution certificate and provisioning profiles

Sign the iOS app for App Store Connect and the ad-hoc device builds
(`mise/tasks/app/bundle-ios.sh`, `luft/ios/distribution/bundle.sh`). A leak
alone does not reach the App Store, because an upload also needs an App Store
Connect credential. It does let someone sign an ad-hoc build that installs on
the registered devices.

- **Rotate**: create a new Apple Distribution certificate (Account Holder or
  Admin), regenerate the four profiles against it (Tuist App Ad Hoc, Tuist App
  Store Connect, Tuist Code Ad Hoc, Tuist Code Live Activity Ad Hoc), and
  replace the items in `tuist-apple-signing`.
- **Revoke**: revoke the certificate in the portal. App Store builds already
  live are not affected. Ad-hoc builds signed with it stop installing.

#### App Store Connect API key (notarization and iOS upload)

Notarizes every macOS artifact (`notarytool --key`) and uploads the iOS app
(`altool --apiKey`). This replaces the app-specific password on Pedro's
personal Apple ID, which signed in to Apple as a person and, per Apple, also
works for that account's iCloud Mail, Contacts and Calendars in third-party
apps. Item `App Store Connect API Key` in `tuist-apple-signing` holds `key-id`,
`issuer-id` and the `AuthKey.p8` file. Vault `swifterpm` needs an item with
the same fields.

- **Create**: App Store Connect → Users and Access → Integrations → Team Keys
  (Account Holder or Admin), role **Developer**. That role can notarize and
  upload builds but cannot submit for review, release, or manage users. Apple
  shows the `.p8` once.
- **Rotate**: create a second key, replace the item's three fields, run a
  release, then revoke the old key.
- **Revoke**: revoke it on the same page. It stops working at once.
- **After the switch**: revoke the app-specific password at account.apple.com
  → Sign-In and Security → App-Specific Passwords, and delete item
  `App Specific Password` from vaults `tuist` and `swifterpm`.

#### Sparkle EdDSA key

Signs the macOS app's update feed entries (`app-release.yml`, item
`Tuist App Private Sparkle Key` in `tuist-sparkle`). Installed apps trust the
public key in `app/Project.swift` (`SUPublicEDKey`). Sparkle installs an
update when it is signed by that key **or** when it is signed with the same
Developer ID as the installed app, and it lets one update change one of the
two, never both.

- **Rotate or revoke** (leak): generate a new key pair with Sparkle's
  `generate_keys`, put the new public key in `SUPublicEDKey`, sign that
  release with the **old** key or rely on the unchanged Developer ID, and
  replace the vault item. Installed copies move to the new key when they take
  that update. Delete the old private key everywhere afterwards.
- If the EdDSA key and the Developer ID certificate leaked together, an
  attacker who can also write the feed (the `appcast` release asset on
  `tuist/tuist`) can push an update every installed copy accepts. Treat that
  as the Developer ID case above, with a forced re-download.

#### Google Play upload key and publishing service account

`release-android` signs the bundle with the upload key (`Google Play
release.keystore` document and `password` field in `tuist-google-play`) and
publishes with a Google Cloud service-account JSON key (same item). The app
uses Play App Signing, so users' devices only see Google's app signing key.

- **Upload key, rotate or revoke**: make a new keystore, export its
  certificate (`keytool -export -rfc -keystore … -alias tuist -file upload_certificate.pem`),
  and request an upload key reset in Play Console → Play app signing (account
  owner). Google takes about two days. Replace the keystore and password in
  the vault once the email confirms the new key.
- **Service account, rotate**: create a new JSON key in Google Cloud, replace
  the vault field, publish, then delete the old key. **Revoke**: delete the
  key in Google Cloud. Removing the account from Play Console → Users and
  permissions also takes its Play access away whatever credential it uses.
- **Better**: Gradle Play Publisher supports Application Default Credentials,
  so the job can use Workload Identity Federation from GitHub's OIDC token
  and the JSON key can go. Not done yet: it needs a workload identity pool in
  Google Cloud.

#### Gradle Plugin Portal key and secret

`gradle-release.yml` publishes `dev.tuist` with `GRADLE_PUBLISH_KEY` and
`GRADLE_PUBLISH_SECRET` from `tuist-gradle-plugin-portal`. The key belongs to
the `tuist` portal account (contact@tuist.dev), which owns `dev.tuist`. The
portal has no trusted publishing.

- **Rotate**: while no Gradle Release run is in progress, open the account's
  API Keys tab on plugins.gradle.org, choose "Generate new publishing key",
  write the new key and secret to both items, then delete the old key with
  its edit button. The next Gradle Release run proves the new key.
- **Revoke** (leak): delete the key on the API Keys tab right away, then
  generate a new one as above. Check the plugin's versions on
  plugins.gradle.org against our `gradle@` tags for releases we did not make,
  and email `security@gradle.com` about any you find.

#### Hex packages (condukt, noora, tuist_ex)

The three publish jobs use Hex Workload Identity (Hex 2.6+, OTP 27+): hex.pm
exchanges the job's GitHub OIDC token for a 15-minute token that can publish
one package, and only when the token names `tuist/tuist`, the package's
workflow file and the `hex-publish` environment. There is no stored key.

- **Set up** (a full owner with 2FA, once per package): on hex.pm, package →
  Settings → Workload identities, add repository owner `tuist`, repository
  `tuist`, the workflow file (`condukt-release.yml`, `noora-release.yml` or
  `tuist-ex-release.yml`) and environment `hex-publish`. Then turn on
  Settings → Staged publishing, so a release CI publishes waits for a person
  with 2FA to approve it. With staging on, `tuist-ex-release.yml` and
  `condukt-hex.sh` see the package as unpublished (404) until it is approved.
- **Revoke**: remove the workload identity on hex.pm. Tokens already issued
  expire within 15 minutes.
- **After the switch**: revoke the key behind the old `HEX_API_KEY` on
  hex.pm (Dashboard → Keys) and delete the repository secret. It was one key
  for all three packages, and any key set in a job takes precedence over
  Workload Identity.

#### Rollout from the shared `tuist` vault

Done by a person, in this order, because a workflow change that lands before
its environment exists fails that release:

1. Create vaults `tuist-apple-signing`, `tuist-sparkle`, `tuist-google-play` and
   `tuist-gradle-plugin-portal`, and move each item there, keeping its item and
   field names.
2. Create the App Store Connect API key and its item in `tuist-apple-signing`
   (and `swifterpm`).
3. Create one read-only service account per environment in the table, and the
   GitHub environments with a `main`-only deployment branch policy and the
   `RELEASE_OP_SERVICE_ACCOUNT_TOKEN` secret.
4. Add the Hex workload identities.
5. Push the workflow and script changes, then watch the next release of each
   product.
6. Revoke the app-specific password and the Hex key, delete `HEX_API_KEY`,
   and delete the moved items from vault `tuist`. The repository-level
   `OP_SERVICE_ACCOUNT_TOKEN` then reaches only the Cloudflare token and the
   Tuist Automation GitHub App key.
7. Because every item here was readable by the old repository-level token
   from push jobs without an environment, rotate each of them once by the
   procedures above (the Developer ID and Distribution certificates, the
   Sparkle key, the Play service-account key, the Gradle key) and fill in the
   expiry table.

### GitHub tokens in CI

No workflow holds a personal access token. The four former PATs
(`TUIST_RELEASE_GITHUB_TOKEN`, `TUIST_CLI_GITHUB_TOKEN`,
`TUIST_APP_GITHUB_TOKEN`, `TUIST_DEPLOY_GITHUB_TOKEN`) belonged to the machine
user `tuistit`, never expired, and were exposed to every step of up to 60
workflows, including jobs that build pull request code. A job now uses the
first of these that is enough:

1. **`GITHUB_TOKEN`** (`github.token`), with the job's `permissions:`. It covers
   everything inside `tuist/tuist`: checkouts, mise downloads, releases and tags
   on main's current commit, GHCR pushes, and dispatching this repository's
   workflows.
2. **Tuist CI GitHub App**, read-only, for pull-request-reachable jobs.
   `actions/create-github-app-token` mints the token from the repository
   variable `TUIST_CI_APP_CLIENT_ID` and secret `TUIST_CI_APP_PRIVATE_KEY`.
   Uses: cloning the private `tuist/TuistCacheEE` submodule (`contents: read`
   on `tuist` and `TuistCacheEE`) in `cli.yml`, `tuist-project-tests.yml`,
   `tuist-project-coverage-backfill.yml`, the CLI release build and the deploy
   cascade's acceptance job; and team-membership checks (`members: read`) in
   `app.yml` and `community-notifications.yml`. Fork pull requests get no
   secrets and skip those steps, as before.
3. **Tuist Automation GitHub App**, for writes `GITHUB_TOKEN` cannot make, only
   in release and deploy jobs that run on main. The
   `.github/actions/github-app-token` composite reads the key from 1Password
   (`op://tuist/Tuist Automation GitHub App`) and requires explicit
   repositories and permissions:

| Need | Workflows | Repositories | Permissions |
| --- | --- | --- | --- |
| Create a tag or ref at a commit whose workflow files differ from main's (release branches, patch releases, a main that moved during the run) | `cli-`, `server-`, `kura-`, `pulse-build-publish.yml`, the four `*-rc.yml` branch cuts, `app-release.yml`, `gradle-release.yml`, `tuist-ex-release.yml`, `condukt-release.yml`, `runner-image-release.yml`, `linux-runner-image-release.yml`, `atlas-release.yml`, `server-production-deployment.yml` (`tag-infra-releases`, and the Helm release in `publish-releases`) | `tuist` | contents, workflows: write |
| Dispatch the Homebrew formula and cask workflows | `cli-build-publish.yml`, `app-release.yml` | `homebrew-tuist` | actions: write |
| Push distributions | `install-action.yml` | `install` | contents: write |
| | `cache-volume-action.yml` | `cache-volume`, `cache-volume-buildkite-plugin`, `cache-volume-gitlab` | contents: write |
| | `runner-cache-actions.yml` | the nine in `ci/runner-caches/distributions` | contents: write |
| | `skills-release.yml` | `agent-skills`, `agent-plugin`, `cursor-plugin`, `claude-plugin` | contents: write |

`mise-lock.yml` and `update-tuist-cli.yml` already used this App, with the
App's full permission set; narrowing them is a follow-up.

Installation tokens expire after an hour and the action revokes them when the
job ends, so jobs mint them right before use. Publish jobs that check out a
release branch load the composite from the workflow's own revision
(`.github-app-token/`), since older branches do not contain it.

Tradeoff: minting through 1Password puts `OP_SERVICE_ACCOUNT_TOKEN`, which can
read the whole `tuist` vault, into the env of one step in each of these jobs.
Storing the Automation App's key as a secret of a main-only GitHub Environment
instead would keep that token out of them.

Rotation: each App holds up to 25 private keys. Generate a new key, update
1Password (Automation) or `gh secret set TUIST_CI_APP_PRIVATE_KEY` (CI), run
one release or pull request, then delete the old key in the App's settings.
There is nothing to revoke per run.

#### PATs that remain

Each needs a named owner, a fine-grained token, and an expiry of at most 90
days. Record the owner and expiry here when you create or rotate it.

| Item | Consumer | Scope it needs | Owner | Expiry | Why it stays |
| --- | --- | --- | --- | --- | --- |
| `GITHUB_TOKEN_UPDATE_PACKAGE_RELEASES` (`tuist-k8s-<env>`) | Server: `Tuist.GitHub.Releases`, `Tuist.Docs.ReleaseStatus` | Public repositories, read-only; no permissions | unassigned | unset | Only raises the API rate limit for public reads. An installation token of the server's GitHub App would do; that needs server code. |
| `REGISTRY/REGISTRY_GITHUB_TOKEN` (`tuist-k8s-<env>`) | `swift-registry-sync` | Public repositories, read-only | unassigned | unset | Fallback only once `swiftRegistrySync.githubAppInstallation` is set, which the managed overlays do not set yet. Remove the fallback after that runs green. |
| `SEARCH_GITHUB_TOKEN` (`tuist-k8s-<env>`) | Typesense indexers (`search/bin/index-github*`) | Public repositories, read-only | unassigned | unset | Shell indexers cannot mint App tokens. |
| `KAMAL_REGISTRY_PASSWORD` (vault `cache`) | Cache (Kamal) deploy | — | `cschmatzler` | — | Being replaced by the deploy job's `GITHUB_TOKEN` (cache stack work, not yet on main). Revoke after the first green Cache Deploy. |

A read-only public PAT cannot write anything, so a leak costs rate limit, not
integrity.

## Cluster CAs and ServiceAccount signing keys

There is no tested in-place procedure for the workload clusters. Cluster API's
kubeadm provider generates `org-tuist/tuist-<env>-{ca,etcd,proxy,sa}` once and
does not rotate them. Pick by what leaked:

- **An admin kubeconfig or client certificate leaked, the CA did not.** The
  certificate stays valid until it expires (one year for kubeadm client
  certificates). There is no CRL in Kubernetes. Options, from cheapest:
  block the API endpoint at the network (the load balancer, see
  [incident-containment.md](incident-containment.md#cut-access)) for addresses other
  than the ones you trust, then replace the CA by rebuilding the cluster.
- **The CA or SA key leaked** (etcd, a control-plane node or the mgmt
  cluster's `org-tuist` Secrets). Treat the cluster as lost: create a new
  Cluster CR (new name, so CAPI mints new PKI) per
  [onboarding](k8s/onboarding.md), deploy the platform and the release to it,
  move traffic (DNS and load balancers), then delete the old cluster. Postgres
  and ClickHouse move by backup restore; Kura caches rebuild. This is the long
  pole of a full rotation; estimate it during a rehearsal.
- **SA signing key only.** The API server accepts several
  `--service-account-key-file`s, so an in-place rotation is possible: add the
  new public key next to the old one through a ClusterClass `files` patch, roll
  the control plane, switch `--service-account-signing-key-file`, wait out the
  longest projected token lifetime, drop the old key, roll again. Untested here;
  rehearse on staging before relying on it. Every pod gets a fresh projected
  token automatically; long-lived token Secrets (CI deployer, tart-kubelet) must
  be re-minted.

Until a CA is replaced, an API server audit log is the only way to see what a
leaked identity did; see below.

## Management cluster (Talos)

The mgmt cluster holds every workload cluster's PKI and kubeconfig, the Hetzner
tokens and the Flux GitHub App. Compromise of it is compromise of every
cluster.

- Talos API credentials (`talosconfig: tuist-mgmt`, vault `Development`) are
  client certificates under the Talos OS CA. Talos supports rotating both its OS
  CA and the Kubernetes CA with `talosctl rotate-ca` (Talos 1.7+, cluster runs
  1.13). **Unverified here:** rehearse it on a throwaway Talos cluster first,
  then run it from a machine on the tailnet, and store the new talosconfig in
  1Password.
- The ephemeral `talos-patcher` credential exists only during a
  `mgmt-cluster-apply` run ([`k8s/mgmt/talos/README.md`](k8s/mgmt/talos/README.md)).
- Changing `cluster.controlPlane.endpoint` invalidates every ServiceAccount
  token (`patches/50-api-endpoint.yaml`); do not do it as part of a rotation by
  accident.

## API server audit log

The workload clusters can record **who read which Secret and who requested
which ServiceAccount token**, at Metadata level: user, groups, source IP, verb,
object name and response code, never the object body. Nothing else is
recorded. Both halves default off:

1. **Policy (ClusterClass).** Set the `apiServerAuditLog` variable to `true` on
   one Cluster CR (`infra/k8s/clusters/workloads/<cluster>/cluster.yaml`,
   `spec.topology.variables`). That renders `/etc/kubernetes/audit-policy.yaml`
   and the API server flags (`--audit-log-path=/var/log/kubernetes/audit/audit.log`,
   JSON, 30 days, 10 files of 100 MB) and **rolls that cluster's control
   plane**. Merge one cluster at a time, staging first, and wait for the
   KubeadmControlPlane to report every replica up to date.
2. **Shipping (k8s-monitoring).** Then set
   `k8s-monitoring.global.apiServerAuditLogs: true` in that cluster's
   `values-<env>.yaml`. `alloy-control-plane` tails the file on each
   control-plane node and pushes it to `alloy-receiver`, which forwards it with
   the Loki credentials it already holds. Setting it before step 1 has finished
   only tails a file that does not exist yet.

Verify on each control-plane node after rollout:

- The API server is Ready and its manifest contains `--audit-policy-file`.
- Lines arrive: `{service_name="kube-apiserver-audit", cluster="tuist-<env>"}`
  in Grafana Loki.
- A known read shows up: as a person with Secret read, `kubectl -n <ns> get
  secret <some-secret> -o name`, then find it:

  ```logql
  {service_name="kube-apiserver-audit"} | json
    | objectRef_resource="secrets" | user_username=~".*<you>.*"
  ```

Queries during an incident:

```logql
# Who read Secrets outside the identities that are expected to
sum by (user_username) (count_over_time(
  {service_name="kube-apiserver-audit"} | json | objectRef_resource="secrets"
    | user_username!~"system:serviceaccount:platform:.*external-secrets.*|system:node:.*" [1h]))

# Every read of the ESO 1Password token
{service_name="kube-apiserver-audit"} | json
  | objectRef_namespace="onepassword" | objectRef_name="onepassword-sa-token"

# ServiceAccount tokens minted, by requester and target
{service_name="kube-apiserver-audit"} | json | objectRef_subresource="token"
```

Limits:

- Shipped events are kept for Loki's 30-day retention
  ([log-review.md](log-review.md)); the files on the nodes keep up to 30 days
  or 1 GB, whichever comes first, and disappear when CAPI replaces the node.
- Lines written while the collector restarts are not shipped (it tails from
  the end), but they stay in the file on the node.
- Volume has not been measured: list and watch by controllers (ESO,
  cert-manager, ingress-nginx, kubelets) and hourly projected-token refreshes
  all log. Check Loki ingest on staging before enabling production.
- **Management cluster:** Talos already writes an audit log on each mgmt
  control-plane node with its default policy (Metadata for every request,
  `/var/log/audit/kube/kube-apiserver.log`, 30 days), since
  `infra/k8s/mgmt/talos/patches/` sets no `auditPolicy`. Read it with
  `talosctl -n <node> read /var/log/audit/kube/kube-apiserver.log` over the
  tailnet. It is not shipped: mgmt's k8s-monitoring overlay deliberately
  disables logs and has no Loki token. Shipping it needs a decision to add
  one; do not set `apiServerAuditLogs` on mgmt, which has no `alloy-receiver`.

## Gaps

What a full rotation cannot do yet, with the owner where one exists:

1. Rotating the server and Atlas Cloak keys takes three deploys (`Tuist.Vault` and `Atlas.Vault` moduledocs); there is no single-deploy path that keeps old pods able to read new values. The [secret splits](#splitting-reused-secrets) are coded but not yet applied in 1Password and production.
2. Rotate `SECRET_KEYS/password` without a mass reset: no owner.
3. Revoke a leaked admin kubeconfig without replacing the cluster: short-lived
   deploy credentials and the vault split shrink the number of them
   ([deploy-credentials thread](https://ampcode.com/threads/T-01a1e431-0de8-70c5-9ee9-424e73991f95)).
4. Replace a workload cluster's CA or SA key in place: untested; rebuild is the
   procedure.
5. Bulk-revoke and notify customers: [legacy tokens thread](https://ampcode.com/threads/T-01a1e431-0342-75a4-aad7-8fa520029c65).
6. Know the 1Password service-account scopes and GitHub Environment rules: not
   in the repository; record them here after checking the consoles.
7. A timed rehearsal of this document on staging, which is the only way to know
   how long a full rotation takes.
8. Release signing: no single job should hold both Sparkle anchors (the
   `app-release` environment reads the Developer ID and the Sparkle key), the
   Play service-account key should give way to Workload Identity Federation, and
   the Gradle Plugin Portal has no keyless publishing. See
   [Release signing and publishing credentials](#release-signing-and-publishing-credentials).
