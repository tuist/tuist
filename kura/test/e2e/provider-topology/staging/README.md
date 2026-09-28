# Staging replication policy fixture

This fixture runs only in the existing `kura` namespace through the standing
staging Tailscale identity. It creates four disposable Deployments on three
explicitly selected cache hosts, with a unique tenant, temporary CA/JWT, bounded
resources and emptyDir storage. It creates no public ingress, provider networks,
PVCs, or KuraInstance records. All resources carry
`tuist.dev/test=kura-topology-e2e`; verify that selector is unused before applying.

The provider/domain strings are **synthetic test metadata**. Services travel on
the existing cluster underlay. This tests runtime selection and fail-closed
behavior, not physical vRack/VPC routing or private bandwidth.

```sh
node test/e2e/provider-topology/staging/render.mjs \
  ghcr.io/tuist/kura:sha-<commit> /tmp/kura-topology-staging-fixture \
  <cache-host-a> <cache-host-b> <cache-host-c>
kubectl --context tuist-k8s-staging.taild6d7bb.ts.net apply --dry-run=server \
  -f /tmp/kura-topology-staging-fixture/manifest.json
kubectl --context tuist-k8s-staging.taild6d7bb.ts.net apply \
  -f /tmp/kura-topology-staging-fixture/manifest.json
node test/e2e/provider-topology/staging/validate.mjs \
  /tmp/kura-topology-staging-fixture ghcr.io/tuist/kura:<previous-staging-tag>
```

Wait for the image build to succeed before applying. The renderer's output
contains test credentials and is written privately; do not commit it. The
validator reserves local ports 4381–4384 for port-forwarding and requires
kubectl, Node.js, and staging namespace edit/exec permissions. Its JSON evidence
and request logs are written alongside the manifest. Test peer certificates
expire after two days and the client token after one day.

Each canonical endpoint is an auditing nginx sidecar that requires the fixture
client certificate and re-encrypts to the runtime with peer mTLS. The private
endpoint reaches the runtime directly. Canonical logs record source pod IP,
request path, response status and byte count, allowing the test to distinguish
normal discovery from an incorrect public data retry. Both branches remain
authenticated; the sidecar is test instrumentation, not a deployment proposal.

The fault removes TCP 7443 from only replica B's fixture NetworkPolicy, while
keeping canonical TCP 8443 reachable. A Service port edit is insufficient:
existing pooled connections can survive it. The validator must observe the
private probe error, prove canonical status is still reachable, prove
cross-provider data continues, and find zero same-provider data requests in the
canonical logs. It restores the policy in `finally`.

The suite also covers every origin, same-region siblings, a 33 MiB individual
body, missing client certificates, cold sibling backfill, bidirectional overlap
with the previous staging image, upgrade/backfill, and replicated namespace
tombstones. Version rollback and pod deletion affect only these disposable
fixtures. An interrupted test can be recovered by applying its original manifest.

After retaining the evidence, remove only the fixture resources:

```sh
kubectl --context tuist-k8s-staging.taild6d7bb.ts.net -n kura delete \
  deployments,services,configmaps,secrets,networkpolicies \
  -l tuist.dev/test=kura-topology-e2e
```

The managed staging fleet's runtime rollout is separate. Record its previous
`TUIST_KURA_RUNTIME_IMAGE_TAG`, pin the new built tag on the existing server
Deployment, and let the normal Kura reconciler/controller roll instances with
their current strategies. Keep actual topology unset until private underlay
qualification. A later Helm deployment may replace an imperative staging pin;
pass the same `kura_runtime_image_tag` to retain it.
