defmodule Condukt.Sandbox.NetworkPolicy do
  @moduledoc """
  Per-session network policy for sandbox egress.

  Every outbound HTTP request the workspace makes runs through this
  policy. The policy is a struct carrying an ordered list of rules plus
  a default action. Each rule is a 2-tuple `{kind, value}`; the runtime
  walks the rules top to bottom and returns the first non-`:continue`
  answer. If every rule passes, `:default` fires.

  Three rule kinds ship out of the box:

  | kind        | value shape                                          |
  | ----------- | ---------------------------------------------------- |
  | `:allow`    | list of host glob patterns                           |
  | `:deny`     | list of host glob patterns                           |
  | `:decide`   | a 2-arity function, `{module, function}`, a module, or `{module, opts}` |

  Because the rule list is just a keyword list, the example reads
  naturally:

      %Condukt.Sandbox.NetworkPolicy{
        rules: [
          deny: ["*.internal.example.com"],
          allow: ["api.github.com", "*.openai.com"],
          decide: {Condukt.Sandbox.NetworkPolicy.AgentDecider, agent: MyApp.NetGuard}
        ],
        default: :deny
      }

  Glob syntax for the host lists: `*` matches a single DNS label,
  `**` matches one or more dot-separated labels, literal characters
  match themselves (case-insensitive).

  The `:decide` value is a callable that receives a
  `Condukt.Sandbox.NetworkPolicy.Context` and a
  `Condukt.Sandbox.NetworkPolicy.Request` and returns `:allow` or
  `{:deny, reason}`. The callable can take four shapes:

    * A 2-arity function: `fn ctx, req -> :allow end`
    * `{module, function}` (atoms): `module.function(ctx, req)`
    * A module alone: `module.decide(ctx, req, [])`
    * `{module, opts}`: `module.decide(ctx, req, opts)`

  Use `Condukt.Sandbox.NetworkPolicy.AgentDecider` to wrap a
  `Condukt`-defined agent as a decider.

  The knobs that govern how the decide rule is invoked are scoped to
  the rule itself, not the policy. Pass a keyword list as the `:decide`
  value with the callable under `:call`:

      decide: [
        call: {Condukt.Sandbox.NetworkPolicy.AgentDecider, agent: MyApp.NetGuard},
        timeout: 5_000,
        cache: true,
        context_messages: 5,
        context_metadata: %{tenant: "acme"}
      ]

    * `:timeout` — milliseconds the decide runtime waits before
      treating the call as failed. Default `5_000`.
    * `:cache` — `true` (default) to cache decider answers per-session
      per-host.
    * `:context_messages` — maximum recent session messages handed to
      the decider as context. Default `5`.
    * `:context_metadata` — per-session static metadata exposed to the
      decider. Default `%{}`.

  ## Other fields

    * `:default` — `:allow` or `:deny`. Default `:deny` (fail closed).
    * `:redact` — list of regular expressions; matching content in
      request/response bodies and headers is redacted by the sidecar
      before events are emitted.
    * `:max_body_capture` — maximum bytes of body to retain in each
      event. Default `4096`.

  ## Telemetry

  Every request lifecycle step emits one of:

      [:condukt, :sandbox, :network_policy, :request_opened]
      [:condukt, :sandbox, :network_policy, :request_allowed]
      [:condukt, :sandbox, :network_policy, :request_denied]
      [:condukt, :sandbox, :network_policy, :request_closed]
      [:condukt, :sandbox, :network_policy, :request_failed]

  `:request_failed` fires when an allowed request never completes
  cleanly (the workspace rejected the session CA, the upstream was
  unreachable, or the stream broke). `reason` carries the label.

  Measurements: `%{bytes_in: integer, bytes_out: integer}`.
  Metadata: `%{request: Condukt.Sandbox.NetworkPolicy.Request.t(),
  reason: atom() | binary() | nil, matched_rule: %{index:
  non_neg_integer(), kind: :allow | :deny | :decide} | nil, at:
  DateTime.t() | nil}`. `:matched_rule` is the rule that produced an
  allow/deny (`nil` for the default action and lifecycle-only events).

  The decide runtime additionally emits, on decider failure:

      [:condukt, :sandbox, :network_policy, :decider_failure]

  Measurements `%{count: 1}`, metadata `%{reason: :decider_timeout |
  :decider_error | :decider_bad_return}`.
  """

  alias Condukt.Sandbox.NetworkPolicy.Context
  alias Condukt.Sandbox.NetworkPolicy.Decider
  alias Condukt.Sandbox.NetworkPolicy.Hosts
  alias Condukt.Sandbox.NetworkPolicy.Request

  defstruct rules: [],
            default: :deny,
            redact: [],
            max_body_capture: 4096

  @doc """
  Normalises arbitrary policy input into a `t()`. Accepts an existing
  struct, a keyword list, a map, or `nil` (returns the default
  deny-all policy).
  """
  def new(nil), do: %__MODULE__{}
  def new(%__MODULE__{} = policy), do: policy

  def new(opts) when is_list(opts) or is_map(opts) do
    fields = Map.new(opts)

    %__MODULE__{
      rules: Map.get(fields, :rules, []),
      default: Map.get(fields, :default, :deny),
      redact: Map.get(fields, :redact, []),
      max_body_capture: Map.get(fields, :max_body_capture, 4096)
    }
  end

  @doc """
  Walks the rules pipeline. Returns `:allow` or `{:deny, reason}`.
  Reason from a deny rule is propagated verbatim; default-deny reasons
  are `:default_deny` / `:matched_deny_list` / `:decider_timeout`.
  """
  def evaluate(%__MODULE__{} = policy, %Context{} = context, %Request{} = request) do
    walk(policy.rules, context, request, policy)
  end

  def evaluate(%__MODULE__{} = policy, %Request{} = request) do
    evaluate(policy, %Context{request: request}, request)
  end

  @doc """
  Emits the telemetry event for a request lifecycle step.

  The K8s control bridge calls this on every NDJSON frame it decodes
  from the sidecar. `kind` is one of `:request_opened`,
  `:request_allowed`, `:request_denied`, `:request_closed`. `opts` may
  carry `:reason` (deny reason or free-form string).
  """
  def deliver(_policy, kind, %Request{} = request, opts \\ []) do
    :telemetry.execute(
      [:condukt, :sandbox, :network_policy, kind],
      %{bytes_in: request.bytes_in, bytes_out: request.bytes_out},
      %{
        request: request,
        reason: Keyword.get(opts, :reason),
        matched_rule: Keyword.get(opts, :matched_rule),
        at: Keyword.get(opts, :at)
      }
    )

    :ok
  end

  defp walk([], _ctx, _req, %__MODULE__{default: :allow}), do: :allow
  defp walk([], _ctx, _req, %__MODULE__{default: :deny}), do: {:deny, :default_deny}

  defp walk([{:allow, hosts} | rest], ctx, req, policy) when is_list(hosts) do
    if Hosts.matches_any?(req.host, hosts), do: :allow, else: walk(rest, ctx, req, policy)
  end

  defp walk([{:deny, hosts} | rest], ctx, req, policy) when is_list(hosts) do
    if Hosts.matches_any?(req.host, hosts), do: {:deny, :matched_deny_list}, else: walk(rest, ctx, req, policy)
  end

  defp walk([{:decide, value} | _rest], ctx, req, _policy) do
    spec = Decider.spec(value)
    Decider.invoke(spec.call, ctx, req, spec.timeout)
  end

  defp walk([entry | _rest], _ctx, _req, _policy) do
    raise ArgumentError,
          "unsupported NetworkPolicy rule entry: #{inspect(entry)} (expected {:allow, [hosts]}, {:deny, [hosts]}, or {:decide, callable})"
  end
end
