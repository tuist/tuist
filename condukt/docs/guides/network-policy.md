# Network Policy

`Condukt.Sandbox.NetworkPolicy` is the per-session outbound egress
audit and policy layer for the Kubernetes sandbox. Every HTTPS request
the workspace makes is intercepted, evaluated against a policy, and
either forwarded to the real destination or refused. Method, path,
headers, and body show up as telemetry on the BEAM side.

The runtime is shaped like a `Plug` pipeline. You declare an ordered
list of rules, and a per-request walk through the pipeline produces a
decision. The pipeline can mix static host matches with a runtime
decider that defers to code or to another agent.

## Quick start

```elixir
defmodule MyApp.CodingAgent do
  use Condukt

  @impl true
  def sandbox do
    {
      Condukt.Sandbox.Kubernetes,
      namespace: "agents",
      image: "ghcr.io/myorg/agent:1.4",
      network_policy: %Condukt.Sandbox.NetworkPolicy{
        rules: [
          deny: ["*.internal.example.com"],
          allow: ["api.github.com", "*.openai.com"],
          decide: {Condukt.Sandbox.NetworkPolicy.AgentDecider, agent: MyApp.NetGuard}
        ],
        default: :deny
      }
    }
  end
end
```

That is the whole API surface most callers need to know about.

## Policy

```elixir
%Condukt.Sandbox.NetworkPolicy{
  rules: [...],
  default: :deny
}
```

`:rules` is the ordered pipeline, expressed as a keyword list. The
runtime walks it from top to bottom; the first rule that matches
returns the decision. If no rule matches, the policy's `:default`
action fires. The default is `:deny`, which fails closed.

Three rule kinds ship out of the box.

### `:allow` and `:deny`

```elixir
allow: ["api.github.com", "*.openai.com"]
deny: ["*.internal.example.com"]
```

Both match the request's host against a list of glob patterns. `*`
matches a single DNS label, `**` matches one or more.

Because order matters, you can pin per-policy preferences. A `:deny`
for `evil.example.com` followed by an `:allow` for `*.example.com`
denies the one host you care about and allows the rest. Swap the order
and the deny wins for everyone.

### `:decide`

```elixir
decide: fn _ctx, _req -> :allow end
decide: {MyApp.Guard, :decide}
decide: MyApp.Decider
decide: {Condukt.Sandbox.NetworkPolicy.AgentDecider, agent: MyApp.NetGuard}
```

The decide rule defers to a callable. Four shapes are accepted: a
2-arity function, `{module, function}`, a module alone (calls
`module.decide(ctx, req, [])`), and `{module, opts}` (calls
`module.decide(ctx, req, opts)`). The behaviour is
`Condukt.Sandbox.NetworkPolicy.Decider`.

The knobs that govern how the decide rule is invoked are scoped to the
rule, not the policy. Pass a keyword list with the callable under
`:call`:

```elixir
decide: [
  call: {Condukt.Sandbox.NetworkPolicy.AgentDecider, agent: MyApp.NetGuard},
  timeout: 5_000,
  cache: true,
  context_messages: 5,
  context_metadata: %{tenant: "acme"}
]
```

A list value is the configured form; anything else (function, module,
`{module, function}`, `{module, opts}`) is a bare callable that takes
the defaults. `:timeout` defaults to 5000ms, `:cache` to `true`,
`:context_messages` to 5, `:context_metadata` to `%{}`.

The decide rule is terminal. Whatever the callable returns becomes the
request's decision. If you want a tiered policy where the decider only
sees uncertain hosts, put the narrower `:allow` and `:deny` rules
ahead of `decide:`.

## The decider context

When a `:decide` rule fires, the runtime hands the callable a
`Condukt.Sandbox.NetworkPolicy.Context` struct alongside the request.
The context carries:

  * `:session_id` — the gated session's id.
  * `:recent_messages` — the last `:context_messages` entries from the
    session's message history, oldest first (the decide rule's option).
  * `:request` — the request the workspace is about to make.
  * `:metadata` — caller-supplied per-session static metadata (the
    decide rule's `:context_metadata` option). Useful for user
    identity, tenant, purpose.

## Agent deciders

`Condukt.Sandbox.NetworkPolicy.AgentDecider` is a thin wrapper that
runs a `Condukt`-defined agent as a decider. It injects the decision
output schema into the run, so the agent never has to describe a wire
format in its prompt. The agent receives the context and the request
as JSON and the wrapper validates a structured
`%{decision: "allow" | "deny", reason: "..."}` answer:

```elixir
defmodule MyApp.NetGuard do
  use Condukt

  @impl true
  def system_prompt do
    """
    You gate outbound network requests for an AI coding agent. You
    receive the request and recent session context. Allow well-known
    reputable API hosts the task plausibly needs; deny everything else.
    """
  end
end
```

The decision contract (`decision`/`reason`) lives in `AgentDecider`,
not in the prompt: it is passed to `Condukt.run/3` as `:output` and
enforced by structured-output validation. Structured enforcement
requires the native runtime; a non-native runtime adapter ignores the
schema and the decider falls back to JSON-decoding the agent's text.

The decider agent runs as a sub-agent of the gated session, so its
own outbound traffic does not route through the same policy it is
helping to enforce.

## Timeouts and caching

The decide rule's `:timeout` (default 5000ms) bounds how long the
runtime waits for a decider response before treating it as a failure.
On timeout the request is denied with reason `:decider_timeout`.

The decide rule's `:cache` (default `true`) memoises decider answers
per-session per-host. Once the model has said `:deny` to `evil.com`,
the next attempt does not pay another model call.

## Telemetry

The sidecar reports every request lifecycle step over telemetry on the
BEAM side. Attach handlers with `:telemetry.attach/4`:

```
[:condukt, :sandbox, :network_policy, :request_opened]
[:condukt, :sandbox, :network_policy, :request_allowed]
[:condukt, :sandbox, :network_policy, :request_denied]
[:condukt, :sandbox, :network_policy, :request_closed]
[:condukt, :sandbox, :network_policy, :request_failed]
```

`:request_failed` fires when a request was allowed but never completed
cleanly: the workspace rejected the session CA
(`reason: "tls_client_rejected_ca"`), the upstream was unreachable
(`reason: "upstream_unreachable: ..."`), or the stream broke
mid-flight. It is distinct from `:request_closed` (a clean finish) so
you can alert on it: in a correctly configured pod it should never
fire, so a non-zero rate is a misconfiguration signal.

Measurements: `%{bytes_in: integer, bytes_out: integer}`.
Metadata: `%{request: Condukt.Sandbox.NetworkPolicy.Request.t(),
reason: atom() | binary() | nil, matched_rule: %{index:
non_neg_integer(), kind: :allow | :deny | :decide} | nil, at:
DateTime.t() | nil}`.

`:matched_rule` is the decision's provenance on `:request_allowed` and
`:request_denied`: which entry in the `:rules` list produced it. It is
`nil` when the policy `:default` fired (no rule matched) and on
lifecycle-only events.

`:request` carries the full `Condukt.Sandbox.NetworkPolicy.Request`,
including method, path, request headers, response status, and
timestamps where the sidecar could derive them. Pipe these events into
whatever observability stack you already run.

### Decider failures

When a `:decide` rule's callable times out, crashes, or returns
something that is not `:allow | {:deny, reason}`, the decide runtime
denies the request and emits:

```
[:condukt, :sandbox, :network_policy, :decider_failure]
```

Measurements: `%{count: 1}`. Metadata: `%{reason: :decider_timeout |
:decider_error | :decider_bad_return}`. The request itself still
surfaces as `:request_denied` with the corresponding reason; this
event exists so you can track decider health separately from policy
denials.

## Workspace images

The sidecar terminates TLS with a per-session ephemeral CA, so the
workspace's HTTPS client has to trust that CA. The Kubernetes sandbox
arranges that without asking the workspace image to do anything.

Two complementary mechanisms ship CA trust into the pod:

  1. **Env vars** for language stacks that consult them at runtime.
     The pod spec sets `NODE_EXTRA_CA_CERTS`, `REQUESTS_CA_BUNDLE`,
     `SSL_CERT_FILE`, `PIP_CERT`, `CURL_CA_BUNDLE`, and
     `GIT_SSL_CAINFO`, all pointed at `/etc/condukt/ca.pem`. Node,
     Python (`requests`, `httpx`), pip, curl, git, Ruby `Net::HTTP`,
     and others honour these without any image cooperation.

  2. **System-bundle overlay** for tools that read the OS trust
     store directly. The sandbox synthesises a bundle that is the
     Mozilla public CA list plus the per-session CA (assembled by
     `Condukt.Sandbox.NetworkPolicy.CA.trust_bundle/1` from the snapshot
     shipped under `priv/ca-certificates/mozilla.pem`) and mounts it
     via `subPath` at `/etc/ssl/certs/ca-certificates.crt` and
     `/etc/ssl/cert.pem`. Those are the two paths every mainstream
     Linux distro and distroless image use, so static Go binaries,
     OpenSSL CLI tools, and any client falling back to the system
     bundle see Mozilla's roots plus the session CA at the location
     they already expect.

Between the two paths there is no image preparation step. Operators
point `:image` at whatever they were already using
(`debian:bookworm-slim`, `python:3.13-slim`, `node:20-bookworm`, an
internal base, a distroless runtime) and the policy works.

The one stack still not addressed is Java. JVM HTTPS clients read a
JKS truststore, not PEM files. If you need JVM cooperation, install
the CA into the JVM keystore at image build time.

## Sandbox support

| Sandbox       | Network policy support |
| ------------- | ---------------------- |
| `Local`       | Not supported. No reliable enforcement plane on the host. |
| `Virtual`     | Not yet. Will hook into the same layer at the Rust boundary when bashkit gains a network surface. |
| `Kubernetes`  | Supported via the egress sidecar. |

Sandboxes that do not support the network policy silently ignore the
`:network_policy` option so agent definitions stay portable across
backends.

## Limitations

  * **Mixed-protocol h2/h1** connections (client picks one, upstream
    only offers the other) fall back to byte splice for that
    connection. Body capture degrades to bytes-only for that request.
  * **Non-HTTP TLS** flows through correctly at the TCP layer but
    method/path/header capture expects HTTP framing.
  * **Egress to ports other than 80/443** is denied at the Kubernetes
    `NetworkPolicy` layer but not surfaced as a telemetry event.
  * **Control channel** (only when a `:decide` rule is present): the
    BEAM reaches the sidecar over a `pods/portforward` WebSocket,
    which Kubernetes serves over WebSockets only since **1.30**
    (KEP-4006). Older clusters cannot run agent deciders. Static
    `allow`/`deny` rules are evaluated entirely sidecar-side and do
    not need the control channel.
  * **Control channel drop**: if the channel drops, any `:decide`
    request in flight at that instant is denied (the sidecar's
    decide timeout fires). The bridge re-dials with capped backoff,
    so subsequent requests recover; it is not a permanent
    degradation. `allow`/`deny` traffic is unaffected.

## Supervision

When a policy has a `:decide` rule, the control channel is a
supervised process, not a bare one linked into the session:

```
Condukt.Supervisor (application root)
└── ControlChannelSupervisor   DynamicSupervisor, one_for_one
    └── ControlBridge           1 per session, restart: :transient
        └── PortForward         linked + monitored worker
```

This is the standard "dynamic children under the application root"
pattern. `ControlBridge` is a `:transient` child, so:

  * `ControlBridge` monitors the session's owner process. When the
    session goes away there is nothing left to gate, so it stops
    `:normal`. A `:transient` child that stops `:normal` is dropped
    (not restarted): no orphaned bridge or port-forward socket. The
    bridge is not linked to the session, so neither can take the other
    down.
  * A genuine *crash* is restarted by the `DynamicSupervisor`.
  * A control port that is unreachable (at startup or mid-session)
    does not crash: the bridge retries with capped backoff and, after
    its attempt budget, gives up `:normal` (dropped, not restarted),
    so a dead port cannot hot-loop the shared supervisor. `:decide`
    then fails closed via the sidecar's decide timeout. Bounded
    restart intensity on the supervisor caps the impact of a
    pathologically crashing bridge.

Tearing the sandbox down explicitly (`Sandbox.shutdown/1`) stops the
bridge too, and is idempotent if it already went away on its own.

## RBAC

In addition to the existing pod / pods/exec verbs the Kubernetes
sandbox needs, `:network_policy` requires the cluster identity to
create and delete `secrets` and `networkpolicies` in the target
namespace. A policy that uses a `:decide` rule also needs
`pods/portforward` for the BEAM to reach the sidecar control channel:

```yaml
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "create", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "create", "delete"]
- apiGroups: [""]
  resources: ["pods/portforward"]
  verbs: ["create"]
```

See [Sandbox](sandbox.md) for the base RBAC bundle.

## Images

The `condukt-egress` sidecar image is published to
`ghcr.io/tuist/condukt-egress:<version>` on every Condukt release.
`Condukt.Sandbox.NetworkPolicy.K8s.Manifests.default_image/0` resolves
to the tag matching the installed Condukt version. Override with the
`:network_policy_image` option on `Condukt.Sandbox.Kubernetes` when
mirroring or pinning.
