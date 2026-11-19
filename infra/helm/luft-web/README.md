# Luft Web Helm Chart

Standalone chart for the Luft web edge, a static single-page app served at
`https://luft.work`. The image is nginx serving the site Once builds from
[`luft/web/`](../../../luft/web/) (`once build LuftWeb`), with a fallback to
`index.html` for client-side routes.

Luft has its own domain, image, namespace (`luft`), release, and workflow, so
nothing from it is served under `tuist.dev` and it ships without riding the
Tuist server rollout. The pod needs nothing from the cluster: it mounts no
secrets or ServiceAccount token, runs as non-root on a read-only root
filesystem, and its NetworkPolicy admits only the ingress controller and denies
all egress.

## Edge and caching

`external-dns` publishes `luft.work` as a Cloudflare-proxied record, and the
chart issues an origin certificate through the cluster's
`letsencrypt-cloudflare` DNS-01 issuer. Cloudflare caches by the origin's
`Cache-Control` (set in `luft/web/nginx.conf`):

| Path | Cache-Control |
| --- | --- |
| `/assets/*` (content-hashed) | `public, max-age=31536000, immutable` |
| HTML shell and client-side routes | `no-cache` |
| Other files | `public, max-age=300` |
| Errors | none |

Cloudflare's default cacheable extensions cover JS and CSS but not `.wasm`, so
the Cache Rule in `infra/flux/cloudflare-config/luft-work-cache-rule.yaml`
(reconciled by the Cloudflare operator) makes everything under `/assets/`
eligible for cache while still respecting the origin's TTLs. HTML is not
cached, so the shell is always revalidated at the origin and deploys show up
immediately.

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

## Local validation

```bash
helm lint infra/helm/luft-web -f infra/helm/luft-web/values-ci.yaml
helm template luft-web infra/helm/luft-web \
  -f infra/helm/luft-web/values-production.yaml \
  -f infra/helm/luft-web/values-ci.yaml
```

## Production deploy

`.github/workflows/luft-web-deployment.yml` builds the site with Once, packages
it into `ghcr.io/tuist/luft-web`, and deploys it on every push to `main` that
touches the web edge, the core, this chart, or the workflow. Pull requests only
build:

```bash
helm upgrade --install luft-web infra/helm/luft-web \
  --namespace luft --create-namespace \
  -f infra/helm/luft-web/values-production.yaml \
  --set image.tag=<sha-tag>
```
