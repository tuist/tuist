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
activation waits and, independently, 128 proxy streams per pod can be admitted.
A stream releases its activation slot before forwarding, so long transfers cannot
prevent other accounts from starting provisioning. Upload bodies
remain unread during the wait, using transport backpressure. Once ready, the
original HTTP or HTTP/2 gRPC request streams to the regional node, which performs
its normal artifact-level authorization. The gateway never replays uploads.
Timeout returns HTTP 503 with `Retry-After: 2`, or gRPC `UNAVAILABLE`; overload
returns HTTP 429 or gRPC `RESOURCE_EXHAUSTED`. Slow provisioning is not guaranteed
to complete within one request. Streams have five-minute network deadlines.

Only pre-forwarding 429/503 responses carry `X-Tuist-Cache-Activation: pending`.
The Swift cache client can retry those responses with a re-iterable upload body,
honoring `Retry-After` and its bounded retry policy. Single-pass uploads,
ordinary upload errors and proxy transport failures are not replayed through
this exception. The gateway strips the marker from upstream responses.
The Bazel capability probe allows 30 seconds per attempt and up to four attempts
for `UNAVAILABLE`/`RESOURCE_EXHAUSTED`; authorization failures and deadlines stop
immediately. URL derivation still makes no network request.

The 20-second activation wait is a per-request budget, not a pod startup SLA.
Provisioning continues after a timeout. Production archive-to-active analysis
identified lingering PVC deletion as the main source of slow returns; improving
teardown coordination is separate work and does not block removing public
demand registration. Staging validation must cover a timeout followed by a
successful retry, rather than require every activation to finish within 20 seconds.

The existing cache-token exchange signs the trusted edge's coarse origin into
the JWT. Activation verifies that token and uses its origin for regional
ordering and demand persistence before enqueueing provisioning. It never uses
the gateway's location or caller-supplied geo headers. Raw credentials and old
JWTs without the claim remain unattributed; existing placement evidence/defaults
apply. The token reflects the exchange location for at most its 30-minute TTL.
Bazel setup, its credential helper, and `tuist cache config` exchange scoped
tokens too. The Xcode proxy keeps a separate token provider per project and
refreshes each JWT near expiry; it never shares one project's grant with another.
An older self-hosted server returning 404 keeps the raw-credential compatibility
path. Direct proxy integrations without a CLI keep their explicitly supplied
bearer and have no signed origin unless they supply an exchanged token.

Stable DNS intent is independent of the `kura_stable_hostname` flag. That flag
now controls only legacy `/endpoints` hand-out. Disabling it must not withdraw
a hostname that new clients derive locally. All public regions must support
stable DNS before CLI release; private regions remain excluded.

Self-hosted servers and accounts using custom or registered endpoints require
`TUIST_CACHE_ENDPOINT`. Without the override, self-hosted builds and the Xcode
proxy use local storage with a warning; explicit remote configuration commands
report the missing setting. Activation refuses custom/registered accounts with
HTTP 409 or gRPC FAILED_PRECONDITION and enqueues no managed storage. Migrate
those endpoint settings before adopting a new CLI; legacy discovery remains
available to older versions.

Fresh, nonempty public usage reports from trusted managed Kura nodes refresh the
account demand clock. Old rollup replays, empty reports, peer replication and
self-hosted reports do not keep managed storage reserved. Existing legacy
endpoint discovery and runner demand signals remain compatible. Usage covers
successful cache transfers; probe-only and miss-only activity need not keep an
unused instance allocated indefinitely. No Kura runtime change is required.

Publishing an exact regional record switches new DNS resolutions to the normal
route. A client holding the wildcard answer or an existing connection can still
use the proxy. Every request revalidates control-plane routing; no host-only
route cache can pin another origin to a region or reuse a draining target.
Only active, non-moving instances in desired regions with fresh stable readiness
are eligible. This adds a control lookup while a client retains the wildcard
answer, avoiding a separate invalidation protocol. Withdrawal keeps
the existing provider-confirmation and drain barriers. After all exact records
are gone, the wildcard makes the next authenticated request able to wake the
account. The fallback does not require retaining a dormant KuraInstance or PVC.

## Deployment and validation

Both `kuraActivation.enabled` in the Tuist chart and
`cacheDNS.activationIngressClass` in the platform chart are off in every
checked-in overlay. Merging the draft does not deploy the gateway or publish the
wildcard. The internal handler and usage-based demand tracking are additive.

Before releasing the new CLI:

1. Audit registered/custom endpoints and configure explicit overrides for their
   CLI environments. Confirm every managed public region has stable DNS support.
   Deploy the server handler and image containing `/cache-activation` to each
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
