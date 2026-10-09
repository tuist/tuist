# runner-egress-gateway

Gives an account's macOS runner jobs a dedicated egress address. Mac runner
hosts send the guest traffic of those jobs through a WireGuard tunnel to this
gateway, which forwards it to the internet. The design, including the host side
and the dispatch gate, is in [DESIGN.md](DESIGN.md).

## Runtime

One DaemonSet per gateway runs on the egress candidate nodes, in an ordinary
(not hostNetwork) pod with `NET_ADMIN`. The agent, in the pod network
namespace:

- Creates kernel WireGuard interface `wg0` (netlink), MTU 1420, address
  `--tunnel-address`, route `--peer-cidr dev wg0`. The private key is re-read
  from `--private-key-file` on every pass, so a rotated Secret applies without
  a restart.
- Watches Nodes read-only (list/watch). A Node is a peer when it has the
  `tuist.dev/runner-egress-public-key` annotation (base64 WireGuard public key)
  and an IPv4 `InternalIP` inside `--peer-cidr`. AllowedIPs is
  `<InternalIP>/32`, with no endpoint since hosts initiate. Peers are synced by
  diff (add, update, remove one peer at a time), never by replacing the peer
  set, so existing sessions survive. Invalid keys, keys or addresses shared by
  two Nodes, and the gateway's own key are skipped and logged.
- Applies table `inet tuist_egress` atomically with `nft -f -`:
  - forward: from `wg0` out `--out-interface`, only from `--peer-cidr` to
    destinations outside the excluded set; replies back to `wg0`; everything
    else from or to `wg0` is dropped, IPv6 included.
  - excluded set: `--excluded-cidrs` plus `--extra-excluded-cidrs`, always
    with `--peer-cidr` and the tunnel address. IPv6 entries are ignored and
    prefixes covered by another one are collapsed.
  - input on `wg0`: only TCP 8080 to the tunnel address from `--peer-cidr`,
    plus established traffic.
  - postrouting: `masquerade`, or `snat ip to <ipv4>` for `--snat=address:<ipv4>`.
- Requires `net.ipv4.ip_forward=1`. The agent reads it and tries to write it
  when it is 0; with a read-only `/proc/sys` the value inherited by the pod
  network namespace has to be 1, otherwise the gateway is not ready.
- Re-asserts all of the above every `--resync-interval` and on Node changes
  that affect a peer, so drift heals. SIGTERM stops the agent and leaves `wg0`
  in place.

`--snat=masquerade` is phase 1: a `CiliumEgressGatewayPolicy` selecting the
gateway pods then SNATs the pod IP to the account's Floating IP.
`--snat=address:<ipv4>` is phase 2, a direct SNAT on a box that routes the
address.

## Endpoints

| Listener | Path | Meaning |
|---|---|---|
| `<tunnel address>:8080` | `GET /healthz` | 200 when ready; probed by hosts through the tunnel |
| `--probe-addr` | `GET /readyz` | 200 once forwarding is on, `wg0` is configured, the ruleset is loaded and the first peer sync completed (an empty peer set counts) |
| `--probe-addr` | `GET /livez` | 503 when no reconcile pass finished within 3 resync intervals plus a minute |
| `--metrics-addr` | `GET /metrics` | Prometheus |

## Flags

| Flag | Default |
|---|---|
| `--gateway-name` | required; constant label `gateway` on every metric |
| `--private-key-file` | required |
| `--listen-port` | `51820` |
| `--tunnel-address` | `198.18.0.1/32` |
| `--peer-cidr` | `100.64.0.0/10` |
| `--excluded-cidrs` | `0.0.0.0/8,10.0.0.0/8,100.64.0.0/10,127.0.0.0/8,169.254.0.0/16,172.16.0.0/12,192.0.0.0/24,192.168.0.0/16,198.18.0.0/15,224.0.0.0/4,240.0.0.0/4` |
| `--extra-excluded-cidrs` | empty; for cluster pod and service ranges |
| `--out-interface` | `eth0` |
| `--snat` | `masquerade` |
| `--probe-addr` | `:8081` |
| `--metrics-addr` | `:9090` |
| `--resync-interval` | `30s` |

The Kubernetes client uses the in-cluster config, or `KUBECONFIG` outside a
cluster. Logs are JSON on stderr.

## Metrics

All carry `gateway="<--gateway-name>"`.

- `tuist_runner_egress_gateway_peers`: peers configured on `wg0`.
- `tuist_runner_egress_gateway_peer_last_handshake_seconds{node}`: Unix time
  of the latest handshake, 0 if none. Age is `time() - value`.
- `tuist_runner_egress_gateway_peer_rx_bytes_total{node}`,
  `tuist_runner_egress_gateway_peer_tx_bytes_total{node}`.
- `tuist_runner_egress_gateway_sync_errors_total`: failed reconcile passes.

## Layout

- `cmd/gateway/`: flags, Node informer, HTTP listeners, reconcile loop.
- `internal/config/`: flag parsing and validation.
- `internal/peers/`: Node to peer extraction and the peer diff.
- `internal/nftables/`: ruleset rendering (golden files in `testdata/`) and
  the `nft -f -` applier.
- `internal/netdev/`: netlink link setup and the freebind listener (Linux),
  the ip_forward check.
- `internal/gateway/`: the reconciler, HTTP handlers and metrics.

## Tests

```bash
cd infra/runner-egress-gateway
go test ./...
go test ./internal/nftables -update   # rewrite the golden rulesets
```

The logic runs against fakes on any OS. `internal/gateway/netns_linux_test.go`
drives real netlink, wgctrl and `nft` and changes the network namespace it runs
in, so it only runs with `RUNNER_EGRESS_GATEWAY_NETNS_TEST=1`, for example:

```bash
docker run --rm --cap-add NET_ADMIN -v "$PWD:/src" -w /src \
  -e RUNNER_EGRESS_GATEWAY_NETNS_TEST=1 golang:1.25-alpine3.22 \
  sh -c 'apk add -q nftables iproute2 && go test ./internal/gateway -run NetworkNamespace -v'
```

## Releasing

Same flow as `stable-egress-controller`. A conventional commit touching
`infra/runner-egress-gateway/**` makes `server-production-deployment.yml`
build `ghcr.io/tuist/tuist-runner-egress-gateway:<semver>` and tag
`runner-egress-gateway@<semver>` (`mise/tasks/release/components.json`).
`k8s:install-platform` resolves the highest tag reachable from the deployed
commit and sets `runnerEgressGatewayImage.tag` on the platform chart.
`runner-egress-gateway-image.yml` tests pull requests and builds `:sha-*` and
`:latest` images from `main`.
