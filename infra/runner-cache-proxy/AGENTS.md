# runner-cache-proxy

A **host-side** interception proxy for the self-hosted GitHub Actions cache. It
runs on the runner host (Mac mini / Hetzner node), **never inside the guest**, so
the MITM CA private key and the tenant cache token never touch customer-controlled
ground. pf (macOS) / nftables (Linux) DNAT redirects guest `:443` to this proxy.

This is not an in-cluster service: the Docker build emits two host binaries
(`darwin/arm64`, `linux/amd64`) baked into the host-provisioning operator images.

## What it does, per connection

1. **Recover the original destination** the guest dialed before DNAT
   (`internal/intercept`): Linux `SO_ORIGINAL_DST`, macOS `/dev/pf` `DIOCNATLOOK`,
   behind one build-tag interface (`dnat_{linux,darwin,stub}.go`). The syscall
   bodies are on-device integration code; everything downstream is
   platform-independent and unit-tested.
2. **Peek the ClientHello SNI without decrypting** (`internal/sni`) and replay the
   peeked bytes to whichever upstream is chosen (non-destructive).
3. **Route**:
   - SNI **not** on the GitHub-Actions cache allowlist (`internal/allowlist`) →
     blind TCP splice (`internal/splice`), no decryption. Azure blob, cert-pinned,
     and unrelated traffic is never touched.
   - SNI on the allowlist → MITM with an on-the-fly leaf signed by the baked CA
     (`internal/mitm`), then route by path (`internal/router` + `internal/upstream`):
     `/twirp/...CacheService/*` → the local cache-gateway with a **token swap**;
     everything else (`/ArtifactService/*`, OIDC, telemetry, unknown) → genuine
     GitHub with the **original** `Authorization` untouched.

## Security / fail-open invariants

- **Token swap without trusting the guest** (`internal/tokenregistry`): the host
  agent stages one file per guest, named by the guest's NAT source IP, under a
  root-owned directory; the proxy maps source IP → cache token and injects it as
  the bearer to the gateway. The guest holds no cache secret and cannot forge
  another guest's source IP. A lookup miss **fails open** to GitHub (never 401s
  the workflow). On **macOS** the writer is tart-kubelet (per-node, already
  staging per-VM env/token). On **Linux** the runners-controller is a single
  Deployment, not per-node, so the token staging needs a node-local writer
  (folded into the node bootstrap alongside the nftables DNAT + systemd unit);
  that node-local Linux staging is the remaining integration, validated at
  rollout on a canary Hetzner node.
- **Fail open everywhere**: unparseable SNI, unknown path, a tripped breaker
  (`internal/breaker`, health-gated on the gateway `/healthz` plus live failure
  count), or a gateway error all route to genuine GitHub. The proxy never turns a
  cache interaction into something worse than a cache miss.
- **Sticky decision** (`internal/router`): a `(srcIP, sni)` pair's routing
  decision is cached so a multi-request transfer is never half-intercepted.
- **Bounded MITM**: only the GitHub Actions cache coordination hostnames are
  decrypted. The Azure blob hostname is intentionally NOT on the allowlist — the
  gateway mints blob URLs on its own hostname, so Azure blob only appears on the
  fail-open path and must pass straight through.

## Why the runner images need a baked CA + NODE_EXTRA_CA_CERTS

The guest must trust the leaves the proxy mints, so the CA **public** cert is
baked into the runner images' trust stores. The GitHub Actions runner is
Node.js-based and Node ignores the system trust store, so `NODE_EXTRA_CA_CERTS`
must point at the baked CA too (set in the runner images). The CA **private** key
is delivered host-side via bootstrap and never enters an image or a guest.

## Build / test

```
cd infra/runner-cache-proxy
GOWORK=off go build ./...
GOWORK=off GOOS=linux GOARCH=amd64 go build ./...   # exercise the linux dnat path
GOWORK=off go test ./...
```

The platform-independent logic (SNI parse, allowlist, routing + token swap,
token registry, breaker, leaf minting, splice) is fully unit-tested. The DNAT
syscall recovery and the end-to-end pf/nftables wiring are validated on real
hosts at rollout.
