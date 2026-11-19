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
| Repo-level `OP_SERVICE_ACCOUNT_TOKEN` | GitHub repository secret | 53 workflow references; reads vault `tuist` (Cloudflare, Tuist Automation GitHub App, Play keystore, Sparkle key, Gradle publish keys) | Next run | Available to same-repo PR workflows; see the CI thread below. |
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
| Tigris backup keys (`S3_BACKUP_CREDENTIALS`, `atlas-*-backup`, tuist-ops, MDM backups) | per vault | CNPG/barman, ClickHouse backup | CNPG picks up on reconcile; verify the next WAL archive | Scoped to the backup buckets only ([`cnpg/README.md`](cnpg/README.md#backup-configuration)). |
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
| `base` | `TUIST_SECRET_KEY_BASE` | Phoenix `secret_key_base`: session cookies, signed and encrypted cookies, LiveView tokens; dev fallbacks of the keys below | Signs everyone out of the dashboard | Yes. Generate with `openssl rand -base64 64`. |
| `tokens` | `TUIST_SECRET_KEY_TOKENS` | `Tuist.Guardian` JWT signing (`runtime.exs`) | Every Guardian-issued token (sessions, CLI access/refresh tokens) stops verifying; users and CI log in again | Yes, with that impact. There is no second verification key, so it is a hard cut. |
| `cache_tokens` | `TUIST_SECRET_KEY_CACHE_TOKENS` (when `server.config.cacheTokenKey.enabled`) | ES256 keypair for cache tokens (`Tuist.CacheGuardian`) | Outstanding cache tokens fail; Kura re-exchanges | Yes. Keep `cache_token.signing_enabled` semantics in mind: install the key everywhere before switching issuance (see `Tuist.Environment.cache_token_signing_enabled?/1`). |
| `password` | `TUIST_SECRET_KEY_PASSWORD` | **Pepper** appended before bcrypt for user passwords, project tokens, Kura self-hosted client secrets, and the HMAC key of the authentication subject cache | **Every user password and every hashed project token and Kura client secret stops matching.** | **No.** Rotating it is a mass credential reset: users reset passwords, customers re-issue project tokens. Only do it with a customer notice. A pepper leak alone does not expose passwords (they are still bcrypt), so it is rarely worth it. |
| `encryption` (legacy key `V1`) and `encryption_keys` | `TUIST_SECRET_KEY_ENCRYPTION`, `TUIST_SECRET_KEY_ENCRYPTION_KEYS`; `TUIST_SECRET_KEY_ENCRYPTION_CURRENT_KEY` from the Helm value `server.config.encryptionKeys.currentKeyId` | Cloak AES-GCM keys for every encrypted DB column (GitHub/GitLab/Bitrise/Buildkite tokens, customer S3 keys, OAuth client secrets, Slack tokens, MFA secrets, runner payloads). `encryption_keys` is a ring of comma-separated `id:base64` entries (32-byte keys, `openssl rand -base64 32`, id not `V1`); `encryption` stays readable as key `V1`. Values carry their key id in the tag `AES.GCM.<id>` | Removing a key that values are still encrypted under makes those values unreadable | **Yes, in three deploys.** Follow the runbook in the `Tuist.Vault` moduledoc (`server/lib/tuist/vault.ex`): (1) add the new key to `encryption_keys` (`server.config.encryptionKeys.enabled: true` the first time) with `currentKeyId` pinned to the key in use, deploy; (2) set `currentKeyId` to the new id, deploy; (3) run `bin/tuist eval 'Tuist.Release.reencrypt_vault("<id>")'` until it passes, let Oban jobs queued before step 2 drain, remove the old key (`legacyKey: false` for `V1`), deploy. If the old key is compromised, ship steps 1 and 2 together and accept read failures on old pods during that rollout. Hosted production and canary refuse to boot when no key is configured, when the current key is `V1` and shorter than 32 bytes, or when the current key is derived from `SECRET_KEYS/base`; staging still falls back to `base`. |

Other server keys:

| Credential | Where → Secret | Reload | Notes |
| --- | --- | --- | --- |
| `KURA_VOLUME_ROOT_KEYS`, `KURA_VOLUME_TRANSPORT_KEYS` | `tuist-k8s-<env>` → server config Secret | Server restart; CSI node plugins pin the transport public key | Versioned, newest first; follow [`kura-volumes-csi/security/key-management.md`](kura-volumes-csi/security/key-management.md#rewrap-retirement-and-recovery). |
| `TUIST_CACHE_GRANT_PRIVATE_KEY`, `TUIST_LICENSE_CERTIFICATE_BASE64` | `tuist-k8s-<env>` → `<release>-server-external-secrets` | Server restart | The license certificate is issued by Tuist; re-issue only if the signing side leaked. |
| `CACHE_API_KEY` | → server config Secret and `kura/kura-shared-secrets` | Restart server **and** Kura | Shared between server and Kura: switch both in one window. |
| `kura-introspection-oauth-client` | → `<release>-server-external-secrets`, `kura/kura-shared-secrets` | Restart server and Kura | |
| `SERVER_CLUSTER_COOKIE` | → `tuist-server-cluster-cookie` (`OnChange`) | Coordinated replacement of every web pod | [onboarding §5e](k8s/onboarding.md#5e-durable-server-distribution-cookies). |

### Tier 5: databases, storage and internal apps

| Credential | Where → Secret | Reload | Notes |
| --- | --- | --- | --- |
| Postgres roles (`WEB_DATABASE_PASSWORD`, `PROCESSOR_DATABASE_PASSWORD`, `OPS_DATABASE_PASSWORD`, `GRAFANA_DATABASE_PASSWORD`, `SWIFT_REGISTRY_SYNC_DATABASE_PASSWORD`) | `tuist-k8s-<env>` → `<release>-pg-<role>` | CNPG runs `ALTER ROLE` on reconcile; then restart the role's clients | [`cnpg/README.md` → Password rotation](cnpg/README.md#password-rotation). The superuser and replication certificates are CNPG-generated; rotate by deleting the CNPG-managed Secret (CNPG regenerates it) if the cluster is suspected. |
| ClickHouse users (app, `CLICKHOUSE_GRAFANA`, ops) | `tuist-k8s-<env>`; managed ClickHouse renders users from values | Restart server/processor; ClickHouse pods roll on the config checksum | Restricted identity: [`clickhouse/README.md`](clickhouse/README.md). |
| Redis | In-cluster, no external credential | n/a | |
| tuist-ops (`TUIST_OPS_BOT`, synced whole: the JIT bot's Slack credentials and `secret_key_base`; its CNPG cluster and backup key) | `tuist-k8s-production` → tuist-ops Secrets | Restart tuist-ops | Rotate Slack credentials in the Slack app config first. tuist-ops serves the impersonation policy for every env, so restart it in a quiet window. |
| Atlas (~30 items: `atlas-secret-key-base`, `atlas-encryption-key`, `atlas-github-app`, `atlas-google-oauth`, `atlas-slack-company`, `atlas-stripe-api-key`, `atlas-mercury`, `atlas-qonto`, `atlas-apns`, `atlas-license-signing-key`, `atlas-super-admin`, …) | `atlas-k8s-production` → `atlas-app` | Restart Atlas | Atlas holds bank and finance API credentials and the license signing key: treat them as Tier 4. Whether `atlas-encryption-key` can be rotated without losing data is not established here; the server's key-ring mechanism does not cover Atlas. |
| MDM (`MDM` item: NanoMDM and NanoDEP API keys, webhook HMAC key, SCEP CA key, Apple assets) | `tuist-k8s-production` → `<release>-mdm-runtime`, `-scep-ca`, `-assets` | Restart MDM | API and HMAC keys rotate freely. Apple push and DEP material is renewed through Apple's portals ([`mdm/`](mdm/AGENTS.md)). Rotating the SCEP CA re-enrolls every Mac. |
| Slack invite app (`SLACK_INVITATION_APP`) | → `slack-runtime` | Restart | |
| Typesense (`TYPESENSE_API_KEY`, `SEARCH_GITHUB_TOKEN`) | → `typesense-runtime` | Restart Typesense and indexers | |
| Pulse (`PULSE_TOKEN`, `PULSE_SENTRY_WRITER`) | → `pulse-dashboard-auth` | Restart Pulse and Alloy | |
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
| Tuist Automation GitHub App | vault `tuist` | GitHub App | CI only. |
| `GITHUB_TOKEN_UPDATE_PACKAGE_RELEASES`, `GITHUB_TOKEN_UPDATE_PACKAGES`, `REGISTRY/REGISTRY_GITHUB_TOKEN` | PATs | GitHub | Prefer replacing PATs with App tokens. |
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

Referenced by `.github/workflows` (count of references): `TUIST_RELEASE_GITHUB_TOKEN`
(117), `OP_SERVICE_ACCOUNT_TOKEN` (53), `TUIST_CLI_GITHUB_TOKEN` (20),
`TUIST_DEPLOY_GITHUB_TOKEN` (13), `TUIST_APP_GITHUB_TOKEN` (7), `KUBECONFIG` (5),
`HEX_API_KEY` (4), `CACHE_OP_SERVICE_ACCOUNT_TOKEN` (4), `CACHE_SSH_PRIVATE_KEY`,
`CACHE_KAMAL_SECRETS`, `ATLAS_OP_SERVICE_ACCOUNT_TOKEN`,
`COMMUNITY_SLACK_WEBHOOK_URL`, `PENTEST_USER_*`, `SPEC95_STAGING_CACHE_TOKEN`,
`AMP_ORB_ISOLATED_VALIDATION_TOKEN`. Vault `tuist` also feeds CI the Play
keystore, the Sparkle key and the Gradle publish keys.

Rotate each at its issuer and with `gh secret set` (repository or
`--env <environment>`). Signing keys (Sparkle, Play upload key, Gradle/Maven
signing) cannot be revoked silently: a leaked Sparkle key needs a client update
that trusts a new key, and the Play upload key is reset through Google Play
support. Workflow hardening (token scope, pinning, guards) is in
[the CI thread](https://ampcode.com/threads/T-01a1e431-33d5-71a0-9548-f69639c2c9bb).

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

1. Rotating the server Cloak key takes three deploys (`Tuist.Vault` moduledoc); there is no single-deploy path that keeps old pods able to read new values. Atlas's encryption key has no documented rotation.
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
