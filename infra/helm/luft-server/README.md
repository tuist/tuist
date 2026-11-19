# Luft Server Helm Chart

Standalone chart for `https://luft.work`: the Luft server (`luft-server/`),
a Phoenix release that serves the Luft web app it carries in its image (built
by Struo from [`luft/web/`](../../../luft/web/), `struo build LuftWeb`) and
the app's API and sign-in routes on the same origin. Luft has its own domain,
image, namespace (`luft`), release, database and workflow, so nothing from it
is served under `tuist.dev` and it ships without riding the Tuist server
rollout.

## Edge and caching

`external-dns` publishes `luft.work` as a Cloudflare-proxied record, and the
chart issues an origin certificate through the cluster's
`letsencrypt-cloudflare` DNS-01 issuer. Cloudflare caches by the origin's
`Cache-Control`:

| Path | Cache-Control | Set by |
| --- | --- | --- |
| `/assets/*` (content-hashed) | `public, max-age=31536000, immutable` | `Plug.Static` in `LuftServerWeb.Endpoint` |
| HTML shell and client-side routes | `no-cache` | `LuftServerWeb.WebController` |
| `/api`, `/auth`, errors | `max-age=0, private, must-revalidate` | Phoenix's default |

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
helm template luft-server infra/helm/luft-server \
  -f infra/helm/luft-server/values-production.yaml \
  -f infra/helm/luft-server/values-ci.yaml
```

## Production deploy

`.github/workflows/luft-server-deployment.yml` builds the web app with Struo,
packages it with the release into `ghcr.io/tuist/luft-server`, and deploys it
on every push to `main` that touches the server, the web app, the core, this
chart, or the workflow. Pull requests only build:

```bash
helm upgrade --install luft-server infra/helm/luft-server \
  --namespace luft --create-namespace \
  -f infra/helm/luft-server/values-production.yaml \
  --set image.tag=<sha-tag>
```
