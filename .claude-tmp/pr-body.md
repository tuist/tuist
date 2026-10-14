## What changed

Regional Kura gateways can now run on [haproxytech kubernetes-ingress](https://github.com/haproxytech/kubernetes-ingress) instead of ingress-nginx, one region at a time. HAProxy routes on its own `/ready` checks, so a box that loses its heartbeat to the control plane keeps serving.

- **kura-controller**: new `spec.haproxyIngressClassName`. When set, `reconcileHAProxyGateway` renders:
  - a `<instance>-haproxy` Service that pins the primary like the public Service, with `publishNotReadyAddresses: true` and two ports (`http`, `grpc-h2`) that both target the co-hosted `http` container port;
  - `<instance>-haproxy` (HTTP on `/`) and `<instance>-grpc-haproxy` (the four gRPC prefixes as begins-with paths, `server-proto: h2`), with `check-http: /ready` every 1s, the same TLS and hosts as the nginx Ingress (shared through `clientIngressTLS`/`clientIngressRules`), and `haproxy.org/allow-list` for private instances.

  Clearing the field deletes all three objects.
- **Server**: `haproxy_gateway: true` on a region spec renders `<ingress class>-haproxy` into the CR and adds `+haproxy-gw` to the revision so live instances re-apply. Set on ca-east and sa-west.
- **Platform chart**: a `kura-<region>-haproxy` alias per host-network region (chart 1.54.2, HAProxy 3.2.15), disabled by default.
  - Host-network DaemonSet, wildcard certificate as the default certificate, `--disable-http`/`--disable-quic`, 3600s timeouts, the same 4m HTTP/2 upload window and 32-stream bound as the nginx gateways.
  - A frontend rule closes connections for names the gateway does not route, the counterpart of nginx's `ssl-reject-handshake`.
  - A host `CiliumClusterwideNetworkPolicy` denies the stats/health/admin ports (1024, 1042, 6060) from `world`.
  - Enabled side by side (`:8443`, nginx keeps `:443`) for ca-east in staging and canary and for **sa-west in production**.
- **Monitoring**: a `kura-haproxy` scrape job (backend response counters, active servers), HAProxy access-log sampling, and the HAProxy rules documented in `alerts.md`. The rules are created in Grafana at the first cutover.

## Why

On 2026-10-07 between 06:36 and 07:22 UTC the only ap-southeast box lost its heartbeat path to the core cluster about 11 times (packet loss on the OVH Europe to Singapore backbone). Each time:
- the node lifecycle controller marked every pod on the box NotReady;
- the EndpointSlices dropped them;
- the box's own `kura-ap-southeast-ingress-nginx` answered **503 "no active Endpoint"** for healthy Kura pods (about 50 requests).

All 20 ap-southeast instances fired "Kura instance has no ready replicas". The gateway also crashed once with a nil-pointer panic in its watch handler (v1.11.3). Upstream ingress-nginx was retired in March 2026, so it gets no further fixes.

The root cause is that the gateway on the box obeys readiness decided remotely. Kubernetes has no per-pod opt-out from the node controller marking pods NotReady, so the fix has to be in what the gateway routes on.

## Why this approach

- **`publishNotReadyAddresses` on the existing Service with ingress-nginx**: open-source ingress-nginx has no active health checks, so it would keep sending traffic to starting, draining and terminating pods. Rollouts would turn into upload failures.
- **A per-node agent writing EndpointSlices from local probes**: fixes the incident but adds a component in the request path, and keeps an unmaintained gateway.
- **Envoy Gateway**: a larger migration (Gateway API CRDs, a central xDS control plane, rewritten routing objects).

haproxytech keeps the Ingress API, runs its controller next to HAProxy on the box, and updates servers through its runtime API without reloads. The closed pilot in #12506 already worked out its gRPC routing.

A few details matter:
- The separate Service carries `publishNotReadyAddresses`, because haproxytech skips endpoints that are not Ready or are Terminating. A draining pod still leaves when it terminates, and the 1s `/ready` check catches it as soon as preStop flips `/ready`.
- Both Service ports target the co-hosted listener. haproxytech gives each Service port one backend with one protocol, so HTTP keeps HTTP/1.1 (Kura's sendfile path) while gRPC uses h2c, and only that listener serves `/ready`. The gRPC-only listener (4001) existed only for nginx's connection pooling.
- A region moves in two values steps (side by side, then serving on `:443` with the nginx alias disabled). Taking `:443` before the HAProxy Ingresses exist would leave the region unrouted.

## Impact

- No customer traffic moves in this PR: HAProxy listens on `:8443` next to nginx.
- sa-west was picked as the first production region because it has the least traffic (1 box, 6 instances, about 126k gateway requests a week). Its cutover to `:443` is a values-only follow-up after checks on the box.
- Instances in other regions are untouched. For them the controller only does cached reads to confirm the HAProxy objects are absent.

## Validation

- `go test ./...` in `infra/kura-controller` passes. The new tests cover the gateway Service shape, the Ingress pair, host and TLS parity with the nginx Ingresses, the private allow-list and removal. Flipping `publishNotReadyAddresses` and the target port each fails a test.
- `mix test test/tuist/kura/regions_test.exs test/tuist/kura/provisioner/kubernetes_controller_test.exs` passes (162 tests).
- `helm lint` of the platform chart passes. `helm template` renders for the staging and production overlays: the sa-west DaemonSet, ConfigMap and host policy come out as described. Ports 8443/1024/1042/6060 are free on the sa-west box today.
- The rendered Alloy configs for metrics and logs pass `alloy fmt`.
- Staging (ca-east, side by side): in progress. Plan:
  - `/ready`, HTTP upload and download, and gRPC over `:8443`;
  - an incident replay (pod forced NotReady: nginx 503, HAProxy 200);
  - a rollout restart under load;
  - an unknown-name connection close;
  - metrics in Grafana.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
