# Regional Kura routing on existing cache machines

Regional routing keeps ingress-nginx and the peer SNI demultiplexer on the
existing cache nodes. It adds no gateway machines. A regional wildcard points
at the healthy ingress processes; the per-account Service still selects one
primary for HTTP and gRPC, and the peer Service still selects its replication
gateway. Moving either selected pod changes the internal destination without
changing the regional DNS answer.

## Configuration and ownership

The Tuist chart's `kuraController.regionalRouting.regions` configures a region's
DNS suffix and its existing ingress DaemonSet. The staging overlay prepares
Canada first:

```yaml
kuraController:
  regionalRouting:
    publishEndpoints: false
    regions:
      - region: ca-east
        domain: ca-east.staging.kura.tuist.dev
        ingressClass: kura-ca-east
        ingressNamespace: platform
        ingressDaemonSet: platform-kura-ca-east-ingress-nginx-controller
```

Use a different domain per environment. Production could use
`ca-east.kura.tuist.dev`. The region identifier and ingress class must match the
server's region catalog. Only host-network public regions are eligible; private
runner caches and cloud LoadBalancer regions retain their existing behavior.
Treat a configured domain as stable once published. Changing or removing it is
a separate endpoint migration, not a capacity adjustment.

The controller prepares two names for each account:

- `acme.ca-east.staging.kura.tuist.dev` for HTTP and gRPC.
- `acme.peer.ca-east.staging.kura.tuist.dev` for peer replication over mTLS.

`RegionalDNS` maintains the ownerless `kura-regional-ca-east-dns` DNSEndpoint,
with `*.ca-east.staging.kura.tuist.dev` and
`*.peer.ca-east.staging.kura.tuist.dev`. A third shared name,
`peer.ca-east.staging.kura.tuist.dev`, uses the public ingress addresses: the
peer namespace otherwise suppresses wildcard resolution for an account named
`peer` under [DNS wildcard existence rules](https://www.rfc-editor.org/rfc/rfc4592.html#section-2.2).
Record count still depends on ingress addresses and regions, not
accounts. The controller reads ready, non-terminating pods
owned by the configured ingress DaemonSet and the region's peer-demux
DaemonSet. Addresses are taken only from Ready, uncordoned, non-evacuating
nodes; external IPs are preferred, and private addresses are excluded. The
public and peer planes have independent address sets. Cache pod placement is
not an input. IPv4 and IPv6 produce A and AAAA records respectively.

The loop refreshes every 30 seconds and emits 60-second TTLs. An API read
failure preserves the previous DNS state. A successful observation of no
healthy ingress withdraws that plane's wildcard addresses. Legacy exact-name
records retain their last targets until a healthy regional replacement exists,
so a preparation typo cannot erase a working compatibility path. Existing
connections and resolver caches are not moved by this change. This is availability filtering
and distribution across addresses, not bandwidth-aware balancing or instant
failover. In particular, one long-lived gRPC connection stays on one ingress.

The controller adds each regional public wildcard to its existing shared
Certificate's SANs, retaining `*.kura.tuist.dev`. It does not issue one public
certificate per regional account. Regional HTTP/gRPC aliases are added to an
Ingress only after the shared Secret covers them. A prematurely configured new
canonical host waits for that Secret instead of ordering an individual
certificate. The peer certificate retains the account CA and covers both old
and new peer names. The SNI demux passes TLS through; Kura continues performing
mutual authentication, and the runtime's existing certificate reload picks up
the expanded leaf.

Public/gRPC Ingresses in configured regions opt out of external-dns's Ingress
source. Otherwise their exact hostname rules would recreate the linear record
population even though a wildcard exists. The CRD source remains responsible
for both the regional wildcard and retained legacy records.

## Migration

1. Deploy the platform policy granting host/remote-node ingress to the cache
   port and the mTLS peer port. The policy is additive to per-account policy;
   JWT authorization and account-scoped mutual TLS remain enforced by Kura.
   Complete any earlier account-wide peer LoadBalancer migration first. The
   regional path deliberately leaves those old LBs alone rather than running
   their old-host migration state machine against a different canonical name.
2. Deploy controller/chart configuration with `publishEndpoints: false`.
   The chart grants read access to ingress readiness in the named namespace.
   The controller adds the regional wildcards to the shared certificate,
   prepares account routes and peer SANs, and preserves existing public and
   peer hostnames in controller-owned CR annotations. Their exact DNS records
   now target regional ingress addresses, independently of the primary.
3. Wait for the shared Certificate to be Ready and verify public DNS contains
   only the expected regional addresses. From outside the cluster, force each
   individual address with the intended hostname/SNI and exercise HTTP, gRPC
   reads and streaming uploads, and authenticated peer transfers. Verify the
   leaf actually served by each runtime includes the new peer name. Test that
   invalid credentials and unknown accounts still fail. Exercise primary
   changes between machines and connection draining under sustained gRPC load.
   A readable Secret or a ready nginx pod alone does not prove that path.
4. Set `publishEndpoints: true` for the prepared region list. The chart supplies
   `TUIST_KURA_REGIONAL_DNS_DOMAINS` to the server. HTTP, gRPC and peer URL
   generation use that domain, and a domain-specific manifest revision causes
   existing CRs to converge. Monitor endpoint adoption, failures, and regional
   ingress/backend bandwidth. New accounts in the migrated regions get no
   individual public or peer DNS record.
5. Retain legacy aliases while static clients or peers still need them. The
   annotations `kura.tuist.dev/legacy-public-hosts` and
   `kura.tuist.dev/legacy-peer-hosts` contain JSON arrays. They persist across
   server reconciles and controller restarts. Do not clear them during initial
   rollout. After all supported clients have moved, old connections have
   drained, and an explicit retirement has been reviewed, an empty array
   retires that plane's old routes and DNS. The controller does not rediscover
   deliberately cleared aliases from its old resources. Newly provisioned
   regional instances start with empty arrays.

Rollback endpoint publication by setting `publishEndpoints: false`, while
keeping the regional controller configuration, wildcard DNS, certificates and
aliases. For accounts created after publication, the controller creates the
legacy names when the server restores them in the CR spec. Clients already
holding new URLs must continue to resolve and route.
Do not downgrade to a controller that predates regional routing after clients
have adopted these names. Do not remove the regional DNSEndpoint or its
certificate names as a rollback.

## Capacity boundary

This changes endpoint routing, not Kura's primary/replication semantics or the
current pod-level shaping and placement reservations. Forwarding can consume
another node's network budget. Existing per-node floors do not become a
pool-wide bandwidth guarantee; validate aggregate ingress demand before each
regional cutover. The Kubernetes cross-node path is not proof of a provider
private-network path. Dedicated gateway procurement, regional admission,
load-aware gateway selection and independent backend network sizing remain
separate work.

The earlier staging transport benchmark compared local and remote forwarding
under a roughly 900 Mbps ceiling. It is not validation of this controller's
DNS lifecycle, production-shaped policy or higher network capacity. This
implementation's automated coverage includes primary changes,
legacy preservation, wildcard TLS gating, DNS suppression, readiness-based
address withdrawal, and peer SAN/route compatibility.
