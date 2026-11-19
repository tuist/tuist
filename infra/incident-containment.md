# Taking the platform offline: containment procedure

What to do in the first hour when platform secrets may be in an attacker's
hands: preserve evidence, stop the attacker's access, and take customer-facing
services offline if they could be abused. Rotation comes after, in the order of
[credential-rotation.md](credential-rotation.md).

This is the managed platform's technical procedure. The company process
(roles, notification duties, the BSI-based response plan) is in the handbook:
[Incident response management](../handbook/handbook/security/human-and-incident-management/incident-response-management.md).

Every step here is a production write and is done by people. On canary and
production the writes need an elevation whose intent names the incident, or the
break-glass admin kubeconfig (`kubeconfig: tuist-<env>`, see
[onboarding → Workload-cluster incident recovery](k8s/onboarding.md#workload-cluster-incident-recovery)).
If the admin kubeconfigs themselves are suspected, use them anyway for
containment: the attacker already has them, and you will replace them later.
Agents may gather read-only evidence through their normal door and draft
commands; they do not run these steps (see
[Cluster access for agents](AGENTS.md#cluster-access-for-agents)).

## Decide the scope

Answer three questions and write the answers in the incident channel with a
timestamp. They decide how much of this page to run.

1. **What is suspected?** One credential, one system (a host, a cluster, an
   internal app), a vault, or "unknown internal access" as in the Bitrise case.
2. **Can it reach customer data or customer machines?** Database and object
   storage credentials, `SECRET_KEYS/encryption`, cluster admin, runner hosts,
   the GitHub Apps installed on customer repositories.
3. **Is it still active?** Ongoing reads in the audit trails, unknown sessions,
   changes nobody made.

| Scope | Run |
| --- | --- |
| One credential, no customer reach | Evidence for that system, then its row in [credential-rotation.md](credential-rotation.md). No downtime. |
| One credential with customer reach, or one system | Evidence, [Cut access](#cut-access) for that system, rotate its tier and everything it could read. |
| A vault, a cluster, the mgmt cluster, or unknown | Everything below, in order. Take the platform offline. |

Taking the platform offline costs customers their CI. Bitrise judged it
worth it; the point of deciding up front is that nobody debates it at 3am.
The incident lead decides; one of Pedro or Marek confirms.

## 1. Preserve evidence (before changing anything)

Retention is short: Grafana Cloud Loki keeps 30 days ([log-review.md](log-review.md)),
and audit files on nodes disappear when CAPI replaces the node. Capture first:

- **Logs.** Export the incident window from Loki for: Pomerium access logs
  and the kube-impersonator `orb:` lines (every human and agent kubectl call),
  `{service_name="kube-apiserver-audit"}` where the
  [API server audit log](credential-rotation.md#api-server-audit-log) is
  enabled, the server's request completion logs, and ingress-nginx logs. Save
  them outside Grafana Cloud.
- **Access records.** tuist-ops `tailscale_jit_requests` /
  `tailscale_jit_elevations`, Atlas `mcp_tool_approvals` and audit events
  ([k8s/jit-elevation-audit.md](k8s/jit-elevation-audit.md)), operator grant
  records ([k8s/operator-project-access-audit.md](k8s/operator-project-access-audit.md)).
- **Provider audit logs.** 1Password (Activity / service-account usage),
  GitHub organization audit log, Tailscale configuration and network logs,
  Hetzner/OVH/Vultr/Scaleway/Cloudflare account activity, Google Workspace
  admin log. Export what the provider allows; some keep only weeks.
- **Cluster state.** The mgmt cluster takes hourly etcd snapshots to Tigris
  ([k8s/mgmt/etcd-snapshot.yaml](k8s/mgmt/etcd-snapshot.yaml)); note the latest
  one and copy it. For each workload cluster, dump object state without
  Secrets: `kubectl get all,ingress,externalsecret,rolebinding,clusterrolebinding,serviceaccount -A -o yaml`.
  Copy control-plane audit files (`/var/log/kubernetes/audit/` on workload
  control planes, `talosctl read /var/log/audit/kube/kube-apiserver.log` on
  mgmt) before any node is replaced.
- **Suspected hosts.** Do not wipe a suspected Mac mini or Linux node. Cordon
  it, cut its network (below), and image or keep it for analysis. Machine
  deletion through CAPI reinstalls the host and destroys the evidence.
- **Databases.** Confirm the latest CNPG base backup and WAL archive are intact
  (`kubectl -n <ns> get backup`); they are the point to restore from if data
  was altered.

## 2. Stop deploys and reconcilers

Stop anything that could undo containment or act with credentials you are
about to revoke.

- **CI.** Disable the deploy workflows so a push cannot redeploy:
  `gh workflow disable <file> --repo tuist/tuist` for
  `server-production-deployment.yml`, `server-deployment.yml`,
  `mgmt-cluster-apply.yml`, `tuist-ops-deployment.yml`, `mdm-deployment.yml`,
  `pomerium-deployment.yml`, `cilium-deployment.yml`, `hccm-deployment.yml`,
  `csi-deployment.yml`, `pulse-production-deployment.yml`, `pulse-deployment.yml`,
  `kura-release.yml`, `omada-deployment.yml`, `slack-deployment.yml`,
  `typesense-deployment.yml` and `remote-execution-deployment.yml`
  (`ls .github/workflows/*-deployment.yml` for the current list). If GitHub itself is suspected, disable
  Actions for the repository in its settings. Re-enable with
  `gh workflow enable`.
- **Flux on mgmt.** Suspend the Kustomizations so drift correction does not
  re-apply something you changed by hand
  ([flux/mgmt/README.md → Suspending and resuming](flux/mgmt/README.md#suspending-and-resuming-a-kustomization)):
  `kubectl -n flux-system patch kustomization <name> --type merge -p '{"spec":{"suspend":true}}'`.
- **Cluster API.** Pause every Cluster so CAPI and the providers stop creating,
  replacing or deleting machines with cloud credentials:
  `kubectl -n org-tuist patch cluster <name> --type merge -p '{"spec":{"paused":true}}'`.
  The workload clusters' own CAPI providers (Mac and bare-metal fleets) stop
  when their Deployments are scaled to zero (step 3). Unpause with
  `"paused":false` once the cloud keys are rotated.

## 3. Take services offline

Order: edge first (stops new customer traffic and attacker use of public
endpoints), then workloads that hold credentials, then runners.

**Edge.** Not every hostname goes through Cloudflare: Kura cache endpoints, the
gRPC Once events listener and the regional Kura gateways are DNS-only and
reach the clusters' load balancers directly. So both layers are needed:

- In the Cloudflare dashboard, add a custom WAF rule on the `tuist.dev` zone
  that blocks everything except the status page and the addresses of the people
  working the incident, or turn on "I'm Under Attack" if only abuse needs
  slowing. This is a console change because going through
  `flux/cloudflare-config` waits on git and Flux; record it and fold it back
  into git (or remove it) afterwards.
- Scale the ingress controllers to zero in each workload cluster:
  `kubectl -n platform get deploy,ds -l app.kubernetes.io/name=ingress-nginx`,
  then `kubectl -n platform scale deploy <name> --replicas=0` for Deployments;
  for DaemonSets (regional Kura gateways), patch a non-matching node selector:
  `kubectl -n platform patch ds <name> -p '{"spec":{"template":{"spec":{"nodeSelector":{"tuist.dev/offline":"true"}}}}}'`.
  The Hetzner load balancers then have no healthy targets.
- Undo: scale back to the replica counts in the platform chart values, or
  re-run the platform install (`k8s:install-platform`), which restores them.

**Application workloads** (per env, namespace `tuist` / `tuist-<env>`, release
`tuist`):

```bash
NS=tuist   # tuist-staging, tuist-canary
STAMP=$(date -u +%Y%m%dT%H%MZ)
# Record replica counts first; the incident record and the undo need them.
for ns in "$NS" kura; do
  kubectl -n "$ns" get deploy,sts -o custom-columns=KIND:.kind,NAME:.metadata.name,REPLICAS:.spec.replicas \
    > "replicas-$ns-$STAMP.txt"
done
# The app namespace, except Redis: the server, processor, xcresult processor,
# registry, swift-registry-sync, codebase-search, runners-controller, the CAPI
# provider (cloud and fleet credentials) and the PDC agent.
kubectl -n "$NS" get deploy -o name | grep -v redis \
  | xargs -r kubectl -n "$NS" scale --replicas=0
# kura-controller and kura-activation run in the kura namespace. Stop them
# before the Kura StatefulSets, or the controller scales those back up.
kubectl -n kura scale deploy --all --replicas=0
```

Scaling the server stops Oban jobs with it; the processor has to stop too or it
keeps running jobs against the database. Check the lists against the recorded
files before running them: the namespaces' Deployments change as the chart
does. With `kura-controller` at zero nothing recreates Kura instances; then
scale the Kura StatefulSets if caches must stop serving
(`kubectl -n kura scale sts --all --replicas=0`).
Undo: redeploy the release through `server-deployment.yml` (re-enable it
first), which restores every replica count from values.

**Runners.** With `runners-controller` at zero no new runner pods are
created, but running jobs continue on their hosts. To stop them:
delete the runner pods of each RunnerPool, Linux and macOS (tart-kubelet stops
the VMs); [runners-controller/AGENTS.md](runners-controller/AGENTS.md) has
their labels. Customer jobs in flight
fail. If a runner host itself is suspected, cordon it and take it off the
tailnet (below) instead of deleting it.

**Internal apps.** tuist-ops, Atlas, MDM, the Slack invite app, Typesense and
Pulse each hold their own credentials. Scale the ones in scope to zero. Note
that scaling **tuist-ops** to zero cuts every human's and agent's kubectl on
canary and production: the kube-impersonator fails closed with 502 when the
policy endpoint is unreachable. That is a valid containment lever, but keep the
break-glass kubeconfig at hand before pulling it.

## Cut access

Revoke the paths the attacker could use, in this order. Most of these are also
the first rotation tier; revoking ahead of rotating causes outages, which is
acceptable once the platform is offline.

1. **People.** Sign out and reset suspected accounts in Google Workspace,
   GitHub, 1Password, Tailscale and cloud consoles. Review admin lists on each.
2. **1Password service accounts.** Delete or disable the suspected ones in
   1Password (per-env ESO tokens, CI tokens, `tuist`/`cache`/`atlas` vault
   tokens). Effect: ESO stops syncing (existing Kubernetes Secrets keep their
   values, so running pods are unaffected) and CI can no longer read vaults.
3. **Cluster credentials.** Delete the CI deployer token Secrets
   (`kubectl -n <ns> delete secret github-actions-deployer-token`): long-lived
   ServiceAccount tokens stop working at once. Admin x509 kubeconfigs cannot be
   revoked; contain them at the network, by restricting the API load balancer
   (Hetzner Cloud firewall or load-balancer source rules) to the addresses of
   the people working the incident, then plan the CA replacement in
   [credential-rotation.md](credential-rotation.md#cluster-cas-and-serviceaccount-signing-keys).
4. **Tailnet.** Remove suspected devices and users in the Tailscale admin
   console; revoke auth keys and OAuth clients (`TAILSCALE_*` items). The ACL
   ([tailscale/acls.json](tailscale/acls.json)) is applied by hand, so an
   emergency ACL edit in the console takes effect at once; commit it afterwards.
5. **kubectl doors.** Pomerium (`kube-<env>`) and the orb door
   (`kube-orb-<env>`) both go through the kube-impersonator sidecar in the
   Pomerium pod, so scaling Pomerium to zero in an env closes both for humans
   and agents. Staging's door is the Tailscale operator's API proxy; remove it
   via the tailnet. Open JIT elevations expire on their own; check
   `tailscale_jit_elevations` for active ones.
6. **GitHub Apps.** Suspend the Tuist GitHub App installations or revoke its
   private keys in the App settings if they are suspected: suspending stops all
   customer repository access through the App. The Flux and builders-fleet Apps
   only touch Tuist's own repositories.
7. **Cloud API keys.** Revoke Hetzner, OVH, Vultr, Scaleway, Cloudflare, AWS
   and Tigris keys in their consoles. With CAPI paused (step 2) and the
   providers scaled down nothing should depend on them for now.
8. **Customer-facing tokens.** Bulk revocation of user and project tokens has no
   tooling yet ([legacy tokens thread](https://ampcode.com/threads/T-01a1e431-0342-75a4-aad7-8fa520029c65));
   until it lands, revoke by SQL in a reviewed transaction.

## Tell customers

- Open a Grafana IRM incident with the `affected_service` label on every
  affected component: the status page ([status/](../status/AGENTS.md)) is built
  from it and reflects severity (`critical` shows a major outage). It runs on
  Cloudflare Workers, outside the clusters, so it stays up while they are down.
  Post an update at each milestone.
- Say which customer action is needed and when: rotating credentials they gave
  Tuist (CI provider tokens, S3 keys, SSO secrets), re-issuing Tuist tokens,
  reviewing GitHub App activity.
- Notification duties to customers and authorities follow the handbook's
  incident response plan.

## Bring it back

1. Finish rotation through the tier that was in scope
   ([credential-rotation.md](credential-rotation.md)), and confirm the audit
   trails show no activity by the old identities.
2. Re-enable CI workflows, resume Flux, unpause Clusters.
3. Redeploy each env through `server-deployment.yml` (staging, canary,
   production, as the normal cascade does). This restores replica counts.
4. Restore ingress controllers, then remove the Cloudflare block rule.
5. Watch error rates and the runner queue; restore runners last.
6. Write the incident record: timeline, scope, what was rotated, and how long
   each step took. Update this page and the rotation inventory with what was
   missing.

## Gaps

- No server-side maintenance mode: going offline means scaling to zero, so the
  dashboard shows a Cloudflare error instead of a notice. A static maintenance
  page served by Cloudflare would fix that.
- No single "offline" switch: the steps above are per env and per workload.
  Rehearse on staging and time it.
- Admin kubeconfigs cannot be revoked; only network restriction and CA
  replacement contain them.
- No bulk token revocation tooling yet.
