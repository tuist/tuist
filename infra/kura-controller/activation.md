# Cache activation from the first request

New hosted CLIs derive `<account>.cache.tuist.dev` locally. Resolving a URL must
not allocate storage, measure latency or call an API. Older CLIs can keep using
`GET /api/cache/endpoints`; there is no new public demand endpoint.

## Routing and lifecycle

An optional `*.cache.tuist.dev` Route53 record sends names with no exact DNS
record to two shared, stateless activation pods behind the main ingress. The
pods use ordinary general-purpose workers, no PVCs, no Kubernetes credentials
and no per-account resource reservation. They ship in the controller image but
run as a separate Deployment. Existing exact account latency records retain
precedence and keep warm traffic on the regional gateways. This does not turn
DNS into an outage fallback: an existing unhealthy exact record still wins.

The gateway selects the control plane from the stable hostname's environment
suffix. Production, canary and staging share one DNS wildcard, so there is one
global owner. Cold activation consequently depends on that owner's ingress and
cluster even for the other environments; direct regional traffic does not.

For an actual cache request with an Authorization bearer credential, the gateway
calls `POST /_internal/kura/activate` on the selected control plane. That internal
protocol accepts ordinary and exchanged cache credentials, checks the account,
retained client-name validity and billing, records demand, and enqueues the
existing unique `ProvisionOnDemandWorker` immediately. The worker applies the
normal admission, placement and provisioning rules; it does not wait for the
minute reconciliation tick. Regional ready URLs come from the managed-instance
projection, not arbitrary custom endpoints. The gateway never returns those
URLs to clients and never redirects credentials or proxies back to itself.

Activation waits at most 20 seconds, polling every two seconds. At most 128
requests per pod can be admitted, including active proxy streams. Upload bodies
remain unread during the wait, using transport backpressure. Once ready, the
original HTTP or HTTP/2 gRPC request streams to the regional node, which performs
its normal artifact-level authorization. Failed uploads are never replayed.
Timeout returns HTTP 503 with `Retry-After: 2`, or gRPC `UNAVAILABLE`; overload
returns HTTP 429 or gRPC `RESOURCE_EXHAUSTED`. Slow provisioning is not guaranteed
to complete within one request. Streams have five-minute network deadlines.

Fresh, nonempty public usage reports from trusted managed Kura nodes refresh the
account demand clock. Old rollup replays, empty reports, peer replication and
self-hosted reports do not keep managed storage reserved. Existing legacy
endpoint discovery and runner demand signals remain compatible. Usage covers
successful cache transfers; probe-only and miss-only activity need not keep an
unused instance allocated indefinitely. No Kura runtime change is required.

Publishing an exact regional record switches new DNS resolutions to the normal
route. A client holding the wildcard answer or an existing connection can still
use the proxy. It caches only routing for 30 seconds (at most 1,024 hosts),\nnever authorization; every request carries its own credential to Kura. Withdrawal keeps
the existing provider-confirmation and drain barriers. After all exact records
are gone, the wildcard makes the next authenticated request able to wake the
account. The fallback does not require retaining a dormant KuraInstance or PVC.

## Deployment and validation

Both `kuraActivation.enabled` in the Tuist chart and
`cacheDNS.activationIngressClass` in the platform chart are off in every
checked-in overlay. Merging the draft does not deploy the gateway or publish the
wildcard. The internal handler and usage-based demand tracking are additive.

Before releasing the new CLI:

1. Deploy the server handler and image containing `/cache-activation` to each
   environment. Keep the CLI draft unreleased until activation is reachable.
2. Validate the gateway against a staging fixture using an explicit local DNS
   override or a test ingress target. Do not publish competing environment-wide
   wildcards. Confirm the existing shared certificate covers `*.cache.tuist.dev`.
3. After rollout approval, enable `kuraActivation.enabled` on the one global
   owner (intended: production). Verify both replicas, both ingress routes and
   TLS by pinning a fixture hostname to the main ingress address first.
4. On that same cluster enable platform `cacheDNS.activationIngressClass: nginx`.
   External-dns now reads main-ingress status as well as existing DNSEndpoints;
   its existing `cache.tuist.dev` zone filter and ownership remain in force.
   It publishes the wildcard using the main ingress load-balancer address.
   Regional classes are excluded from this additional source, avoiding a second
   writer for account latency records. Cloudflare keeps excluding this zone.
5. Check authoritative and recursive DNS for a cold fixture and a warm account;
   the latter must still resolve to its regional latency target. Watch for TXT
   ownership remnants or other explicit records suppressing wildcard answers.
6. With a fixture having no live Kura workload, run real HTTP and Bazel gRPC cache
   writes/reads. Verify authorization failures enqueue nothing, exactly one
   provisioning job is admitted per uniqueness window, uploads survive the
   wait, capacity refusal is retryable, and activation time is acceptable.
7. Complete an archival cycle and repeat the first-request wake-up. Verify warm
   traffic refreshes demand without `/endpoints`. Compare direct traffic latency
   and gateway load before publishing the CLI.

Local tests cover the control protocol, credentials, environment/tenant
isolation, immediate job enqueue, request cancellation, retryable failures,
streamed uploads, gRPC trailers and Helm rendering. They do not establish live
DNS propagation, cluster scheduling time, full archival or capacity under load.

## Rollback

Before CLI release, leave or turn both opt-ins off. After new CLIs are released,
retain a functioning wildcard activation path: turning it off would strand cold
accounts. Roll the stateless gateway image back or keep affected accounts warm
while fixing it; do not withdraw regional records or bypass their drain barrier.
The older `/endpoints` endpoint remains available for older versions, but new
clients will not call it as a fallback. Self-hosted clients continue to require
`TUIST_CACHE_ENDPOINT` and do not use this hosted activation infrastructure.
