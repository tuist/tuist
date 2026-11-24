# Luft Server Helm Chart

Standalone chart for `https://luft.work`: the Luft server (`luft-server/`), a headless Phoenix API/auth server and conversation runtime. It does not bundle or serve a web shell; the standalone `luft/web/` frontend is a separate concern. Luft has its own domain, image, namespace (`luft`), release, database and workflow, so nothing from it is served under `tuist.dev` and it ships without riding the Tuist server rollout. Migrating existing conversations from Tuist requires the [offline worker cutover](../tuist/README.md#conversation-runtime-cutover), not just a deploy.

## Edge and caching

`external-dns` publishes `luft.work` as a Cloudflare-proxied record, and the
chart issues an origin certificate through the cluster's
`letsencrypt-cloudflare` DNS-01 issuer. Preserve origin cache controls on API/auth responses; do not add edge caching for authenticated data. This release has no frontend `/assets/` or HTML shell to cache. The legacy `/assets/` Cache Rule in `infra/flux/cloudflare-config/luft-work-cache-rule.yaml` does not provide a frontend and must not be broadened to API/auth routes.

One-time Cloudflare setup, outside this repository:

1. Add the `luft.work` zone (ID `35d2834627c7070a7f687ca722a59c7b`) to the
   Tuist Cloudflare account.
2. Grant the Cloudflare operator's token `Cache Rules:Edit` on `luft.work`.
3. Grant the `cloudflare-api-token` used by the production platform release
   `Zone.DNS:Edit` on `luft.work` (external-dns and the DNS-01 solver share it).
4. Set the zone's SSL/TLS mode to **Full (strict)**.

Production's platform overlay (`infra/helm/platform/values-tuist.yaml`) enables
`luftDNS`, an external-dns instance of its own that watches only the `luft`
namespace and writes only `luft.work`. It uses the `_extdns-%{record_type}.` TXT
prefix because the shared instance's registry names an apex record's ownership
entry `a-luft.work`, outside the zone, and rewrites the record every sync.

## Cutover from luft-web

`luft.work` used to be served by a separate nginx release, `luft-web`. Both
releases claim `luft.work` on `/`, so they cannot run side by side:

1. `helm uninstall luft-web -n luft`. Its Ingress and DNS record go away; its
   certificate Secret, `luft-web-tls`, stays.
2. Run `.github/workflows/luft-server-deployment.yml` right away. This chart's
   Certificate adopts `luft-web-tls` (`ingress.tlsSecretName`), so the origin
   serves a valid certificate at once, and the `luftDNS` external-dns
   republishes the record for this Ingress.

The site is down between the two steps.

## Local validation

```bash
helm lint infra/helm/luft-server -f infra/helm/luft-server/values-ci.yaml
helm lint infra/helm/luft-server \
  -f infra/helm/luft-server/values-production.yaml \
  -f infra/helm/luft-server/values-ci.yaml
helm template luft-server infra/helm/luft-server \
  -f infra/helm/luft-server/values-production.yaml \
  -f infra/helm/luft-server/values-ci.yaml
python3 infra/helm/luft-server/test-clustering.py
```

## Replica clustering

The default single replica runs without Erlang distribution. For two or more
replicas, set `cluster.enabled: true`, `networkPolicy.enabled: true` and
`cluster.cookieExistingSecret` to a Secret in this release's namespace.
The chart rejects unclustered multi-replica deployments and clustered deployments
without that Secret reference or the private network policy. Helm renders
offline; Kubernetes checks that the referenced Secret and key exist at startup.

**Before the first production deployment with this configuration**, an operator
must create the dedicated Password item `LUFT_SERVER_CLUSTER_COOKIE` in the
`tuist-k8s-production` 1Password vault. Check that the item does not already exist
before creating it; never regenerate it during routine deployment or recovery:

```bash
op item create --vault tuist-k8s-production --category Password \
  --title LUFT_SERVER_CLUSTER_COOKIE --generate-password=letters,digits,64 >/dev/null
```

Production enables `cluster.externalSecret.enabled`: the `onepassword`
ClusterSecretStore syncs `LUFT_SERVER_CLUSTER_COOKIE/password` into the dedicated
`luft-server-cluster-cookie` Secret in namespace `luft`, key `release-cookie`.
The ExternalSecret uses `refreshPolicy: OnChange` to avoid timer-driven rotation
and `deletionPolicy: Retain` to preserve the runtime copy on source loss. Missing
or empty source values fail synchronization without generating a replacement.
Verify ExternalSecret `Ready=True` before relying on peer joins; this does not
prove membership. Self-hosters can leave this integration disabled and provision
`cluster.cookieExistingSecret` themselves.

Keep the same high-entropy, private, nonempty whitespace-free value across
replicas, image rebuilds and rolling upgrades. The chart never generates it or
fetches it from the `LUFT_SERVER` OAuth item or any Tuist Secret. Do not reuse
the Tuist server's distribution cookie. A missing key blocks pod startup; an
empty or whitespace-containing value fails distributed release startup without
printing the value. Source edits alone do not synchronize an OnChange resource;
explicitly force synchronization during an approved rotation and coordinate a
full process replacement;
a normal rolling rotation partitions old and new cookie holders.

The chart sets `DNS_CLUSTER_QUERY=<release>-headless.<namespace>.svc`, `POD_IP`
from the downward API, and `RELEASE_COOKIE` from the explicit Secret key.
`rel/env.sh.eex` sets `RELEASE_DISTRIBUTION=name` and
`RELEASE_NODE=luft_server@<pod-ip>` and fixes the distribution listener to TCP
9100. EPMD uses TCP 4369. The headless Service publishes unready pod addresses
so discovery does not depend on HTTP readiness. The app must supervise DNSCluster
with `System.get_env("DNS_CLUSTER_QUERY") || :ignore`, alongside its Phoenix
PubSub and Presence processes. DNSCluster periodically discovers membership;
Channels and Presence deliver events over distributed Erlang, not application
polling.

Only pods matching this release's name and instance labels in the same namespace
can reach TCP 4369/9100 through the chart's ingress and egress policy. The public
Service/Ingress expose HTTP only; the ingress controller has no distribution
access. Keep other namespace policies from adding broader access, since
Kubernetes NetworkPolicies combine additively. Tuist access remains public HTTPS
on TCP 443; the chart grants no private Tuist access.

Before promoting, verify that both nodes see each other, subscribe on one replica
and broadcast on the other, check cross-replica Presence joins/leaves, then replace
a pod and repeat. Local rendering and shell regressions do not prove live cluster
membership or event delivery. To roll back without clustering, first reduce to
one replica, then disable clustering; do not run multiple isolated PubSub islands.

## Production deploy

`.github/workflows/luft-server-deployment.yml` builds the headless release into `ghcr.io/tuist/luft-server` and deploys it on relevant pushes to `main` (the server, Condukt, certificate trust, this chart, or the workflow). It does not build or package the standalone web frontend. Pull requests only build:

```bash
helm upgrade --install luft-server infra/helm/luft-server \
  --namespace luft --create-namespace \
  -f infra/helm/luft-server/values-production.yaml \
  --set image.tag=<sha-tag>
```
