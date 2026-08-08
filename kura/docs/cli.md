# Kura CLI

The `kura` binary both runs a node and inspects one. Running it with no
arguments serves, which is what the release image's `ENTRYPOINT` does and what
the Helm chart relies on. Every other invocation is an inspection command.

```
kura                        # serve (unchanged)
kura serve                  # explicit alias for the same thing

kura runtime inspect        # everything the process holds in memory
kura runtime config         # the configuration the node actually resolved
kura runtime store          # on-disk store counters
kura node status            # readiness, traffic state, and why
kura peer list              # peers, how each was learned, replication health
kura outbox stats           # outbox depth and per-target replication backoff

kura cache trim --cache manifest --to 0     # requires a grant
kura namespace delete <id>                  # requires a grant
kura upload abort <id>                      # requires a grant
```

Resource nouns live at the root rather than under a grouping word, matching the
shape `consul`, `nomad`, `vault`, and `etcdctl` settled on.

## Reaching a node

```
kubectl exec -n kura kura-0 -- kura runtime inspect
```

No arguments are needed inside a pod. The chart already exports `KURA_DATA_DIR`,
and the resolution chain is:

1. The data directory, from `--data-dir` or `KURA_DATA_DIR`.
2. `.kura.runtime.json` in that directory, written at startup, which names the
   control socket.
3. `.kura.control.sock` in the same directory, an HTTP surface over a Unix
   socket.

Output is human-readable on a terminal and JSON when piped, so `--output` is
rarely needed:

```
kura runtime inspect | jq .membership.discovered_only_peers
```

### Why a Unix socket rather than a port

- The reports include the resolved configuration and the full peer sets.
  A network listener means one ingress or NetworkPolicy mistake exposes them;
  a socket in the data directory cannot be reached off-box.
- Authorization becomes "can you exec into this container", which is already the
  boundary the cluster enforces. There is no second auth story to build.
- Liveness detection is free. A clean shutdown unlinks the socket and a crash
  leaves one whose `connect` fails, so the CLI never has to guess whether a
  recorded pid is still the process it wants.

The socket is `0600` and so is the runtime file.

### Why not just read the environment

`src/enrollment.rs` calls `set_var` after startup to inject `KURA_TENANT_ID` and
`KURA_PEERS` into the server process. A freshly exec'd shell sees the
pre-enrollment values, so the environment is not a reliable description of the
running node. Only the process knows what it resolved.

## What this surfaces that `/metrics` cannot

`/metrics` exports 145 metric families and remains the right tool for time
series and alerting. What it cannot carry is identity: Prometheus labels have to
stay bounded, so every entity-scoped fact is aggregated into a count. You can
see `kura_bootstrap_known_peers 7` but not which seven.

State that has no metric at all today:

| State | Why it matters |
| --- | --- |
| Per-target replication backoff | Which peer has stopped accepting writes, its consecutive failure count, and when it retries. The target URL would be an unbounded label. |
| Resolved configuration | The pod spec shows what was requested, not what was resolved after defaults, clamps, and derivation from host resources. |
| Control-plane peer list | The URLs behind the counts, and which peers are configured versus discovered. |
| Discovered-only peer set | Outbox pruning never drops these peers' messages, so this set explains outbox growth that depth alone does not. |
| Bootstrap epoch | Whether an in-flight pass will have its completion discarded. |
| Warm-start flag | Whether the node began its joining cycle with usable local data. |
| Derived memory pool targets | The static limits are metrics; the values in force under current pressure are computed on demand. |
| Semaphore permits and staging budgets | Bootstrap concurrency saturation. |

## Operational notes

- These endpoints are for human-invoked debugging, not polling. `runtime inspect`
  takes the readiness lock (the same one `/ready` uses) and snapshots the
  replication backoff map. Both are released before anything serializes, so a
  single call cannot stall the replication path, but a tight loop is still the
  wrong tool. Use `/metrics` for anything continuous.
- The control socket deliberately outlives the public drain. A stuck drain is
  one of the things most worth inspecting, so it keeps answering until inflight
  requests have finished and the other listeners are down.
- If the socket cannot be bound (an unusual filesystem, or a data directory path
  long enough to exceed the socket path limit) the node logs a warning and
  serves cache traffic normally. Losing introspection never blocks serving.

## Rollout safety

- Bare `kura` still serves. Nothing in the chart, the Dockerfiles, or
  `docker-compose.yml` passes arguments to the binary.
- The control routes are versioned under `/v1` from the first release. The data
  directory is a persistent volume that outlives any pod and rolling updates run
  mixed versions side by side, so a CLI from one image can meet a node from
  another. Routes are additive within `/v1`; the runtime file carries a schema
  version and both sides report a version mismatch rather than misreading each
  other.
- `runtime config` is serialize-only and the CLI forwards it as opaque JSON, so
  adding a configuration field never breaks an older CLI.
- The runtime file and socket live in the data directory root. Nothing
  enumerates that root: segment sweeping, capacity math, and the multipart
  janitor are all scoped to `segments/`, `tmp/`, and the upload subdirectories.
- A socket left behind by a crashed process is removed at startup. That is safe
  because the exclusive writer lock is already held by then, so no live node can
  be listening on it.

## Writes require a grant

Reads are authorized by reaching the socket at all. Writes are not: container
access is a single coarse permission, and a Unix socket cannot tell one human
from another because every process in the container shares a uid.

So a mutating command carries a short-lived **grant**: an EdDSA (Ed25519) JWS
that the node verifies offline against a configured public key.

```
kura namespace delete demo --grant "$TOKEN"   # or set KURA_GRANT
```

Kura is deliberately agnostic about who issues grants. Configure it with any
authority that can sign an Ed25519 JWS:

| Variable | Meaning |
| --- | --- |
| `KURA_CONTROL_GRANT_PUBLIC_KEY` | PEM public key. Not a secret: it verifies, it cannot mint. |
| `KURA_CONTROL_GRANT_ISSUER` | The `iss` this node trusts. |
| `KURA_CONTROL_GRANT_AUDIENCE` | The `aud` this node answers to. Scope it per environment. |
| `KURA_CONTROL_GRANT_MAX_TTL_SECONDS` | Ceiling on `exp - iat`. Defaults to 3600. |

All three of the first must be set together, or none. **With none set, writes are
refused** rather than allowed, so a deployment that never opts in has no write
surface at all.

Claims: `iss`, `aud`, `sub`, `tier` (`write` authorizes mutation), `iat`, `exp`,
plus optional `reason` and `jti` that are carried into the audit log.

What is checked, and why:

- **EdDSA-strict.** The token's own `alg` is never honoured, so a token forged
  with `none` or with `HS256` over the public key is rejected.
- **Asymmetric.** A compromised node holds only a verifying key, so it cannot
  mint a grant for itself or for a peer.
- **No callback to the issuer.** Verification is local, so an issuer outage
  cannot take the cache mesh with it.
- **Bounded TTL.** `exp - iat` is capped, and a future-dated `iat` is rejected
  so it cannot smuggle a long-lived grant past that cap.
- **Fail closed** on every other condition.

Revocation is by short TTL plus key rotation. There is deliberately no
revocation list and no network dependency.

Every authorized mutation and every denial is logged with the subject, the grant
id, the reason, and the operation.

## Referential integrity

The store is not a flat key-value map. A manifest is referenced by the namespace
index and the segment index; an action-cache entry references the CAS blobs it
was built from, plus the reverse map that drives the eviction cascade; a
multipart upload owns staged part files on disk.

Two rules follow, and mutating handlers are written to them:

1. **Composite operations only.** Handlers call `Store` operations that write
   their whole set of keys in one atomic batch, never raw keys. Reaching past
   them could leave a manifest whose segment-index entry still points at it, or
   an action-cache entry whose blobs are gone, and the eviction cascade and the
   serve-side presence gates assume that never happens.
2. **Only converging deletes are offered.** A node-local delete does not
   converge: anti-entropy copies the data back from a peer on the next bootstrap
   pass. `namespace delete` writes a tombstone and enqueues to every replication
   target, so it is durable mesh-wide. A per-artifact delete is deliberately
   **not** offered, because there is no artifact tombstone: it would appear to
   work and then silently undo itself.

`namespace delete` refuses with 503 when the outbox is full, rather than
applying locally without enqueuing.

## Not implemented

- Inspecting a **remote** node. It would mean mounting these routes on the
  internal listener and building an mTLS client. The case it serves, debugging
  node B from node A, is covered today by exec'ing into node B.
- **Per-artifact delete**, for the convergence reason above.
