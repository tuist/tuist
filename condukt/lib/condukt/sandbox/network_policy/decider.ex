defmodule Condukt.Sandbox.NetworkPolicy.Decider do
  @moduledoc """
  Behaviour and runtime for the `:decide` rule on a
  `Condukt.Sandbox.NetworkPolicy`.

  A decider receives a `Condukt.Sandbox.NetworkPolicy.Context` and a
  `Condukt.Sandbox.NetworkPolicy.Request` and returns `:allow` or
  `{:deny, reason}`. Four shapes are accepted as the rule's value:

    * A 2-arity function: `fn ctx, req -> :allow end`
    * `{module, function}` (both atoms): `module.function(ctx, req)`
    * A module atom alone: `module.decide(ctx, req, [])`
    * `{module, opts}` (a keyword list): `module.decide(ctx, req, opts)`

  Use `Condukt.Sandbox.NetworkPolicy.AgentDecider` to wrap a Condukt
  agent module as a decider.

  The knobs that govern invocation are scoped to the decide rule, not
  the policy. Pass the `:decide` value as a keyword list with the
  callable under `:call` plus any of `:timeout`, `:cache`,
  `:context_messages`, `:context_metadata`. A bare callable uses the
  defaults.

  ## Runtime semantics

  Decider invocations run in a separate process bounded by the rule's
  `:timeout` (default 5000ms). On timeout, an exception, or any
  non-`:allow | {:deny, reason}` return value, the request is denied
  with a structured reason and an entry surfaces in telemetry.

  Decisions are cached per-session per-host when the rule's `:cache`
  is true (default). The cache is in-process and dies with the
  session.
  """

  alias Condukt.Sandbox.NetworkPolicy
  alias Condukt.Sandbox.NetworkPolicy.Context
  alias Condukt.Sandbox.NetworkPolicy.Request

  @callback decide(context :: Context.t(), request :: Request.t(), opts :: keyword()) ::
              :allow | {:deny, term()}

  @default_timeout 5_000
  @default_context_messages 5

  @doc """
  Invokes a decider once, in an isolated process bounded by `timeout`
  milliseconds. Used directly by `Condukt.Sandbox.NetworkPolicy`'s
  rule walker when a `:decide` rule fires.
  """
  def invoke(decider, %Context{} = context, %Request{} = request, timeout) when is_integer(timeout) do
    do_invoke(decider, context, request, timeout)
  end

  @doc """
  Normalises a `:decide` rule value into a spec map with `:call`,
  `:timeout`, `:cache`, `:context_messages`, and `:context_metadata`.

  A keyword list is the configured form and must carry the callable
  under `:call`. Anything else (function, module, `{module, function}`,
  `{module, opts}`) is a bare callable that takes the defaults.
  """
  def spec(value) when is_list(value) do
    call =
      Keyword.get(value, :call) ||
        raise ArgumentError,
              "the configured decide form requires a :call entry, got: #{inspect(value)}"

    %{
      call: call,
      timeout: Keyword.get(value, :timeout, @default_timeout),
      cache: Keyword.get(value, :cache, true),
      context_messages: Keyword.get(value, :context_messages, @default_context_messages),
      context_metadata: Keyword.get(value, :context_metadata, %{})
    }
  end

  def spec(callable) do
    %{
      call: callable,
      timeout: @default_timeout,
      cache: true,
      context_messages: @default_context_messages,
      context_metadata: %{}
    }
  end

  @doc """
  Returns the spec for the policy's first `:decide` rule, or `nil` when
  the policy declares no decide rule.
  """
  def policy_spec(%NetworkPolicy{rules: rules}) do
    Enum.find_value(rules, fn
      {:decide, value} -> spec(value)
      _ -> nil
    end)
  end

  @doc """
  Runs the policy's decide rule (if any) and applies the per-session
  decision cache. Used by the K8s control bridge when the sidecar
  sends a `decision_request`. Returns `{decision, updated_cache}`.
  """
  def decide(%NetworkPolicy{} = policy, %Context{} = context, %Request{} = request, cache) do
    case policy_spec(policy) do
      nil -> {default_decision(policy), cache}
      spec -> dispatch(spec, policy, context, request, cache)
    end
  end

  defp dispatch(%{cache: false} = spec, policy, context, request, cache) do
    {run_one(spec, policy, context, request), cache}
  end

  defp dispatch(spec, policy, context, request, cache) do
    case Map.fetch(cache, request.host) do
      {:ok, cached} ->
        {cached, cache}

      :error ->
        decision = run_one(spec, policy, context, request)
        {decision, Map.put(cache, request.host, decision)}
    end
  end

  defp run_one(spec, policy, context, request) do
    case do_invoke(spec.call, context, request, spec.timeout) do
      :allow -> :allow
      {:deny, _} = decision -> decision
      _other -> emit_failure_and_default(:decider_bad_return, policy)
    end
  end

  defp do_invoke(decider, context, request, timeout) do
    parent = self()
    ref = make_ref()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        result = run_decider(decider, context, request)
        send(parent, {ref, result})
      end)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        validate(result)

      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        emit_failure(:decider_error)
        {:deny, :decider_error}
    after
      timeout ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
        after
          0 -> :ok
        end

        emit_failure(:decider_timeout)
        {:deny, :decider_timeout}
    end
  end

  defp run_decider(decider, context, request) when is_function(decider, 2) do
    decider.(context, request)
  end

  defp run_decider({mod, fun}, context, request) when is_atom(mod) and is_atom(fun) do
    apply(mod, fun, [context, request])
  end

  defp run_decider({mod, opts}, context, request) when is_atom(mod) and is_list(opts) do
    mod.decide(context, request, opts)
  end

  defp run_decider(mod, context, request) when is_atom(mod) do
    mod.decide(context, request, [])
  end

  defp validate(:allow), do: :allow
  defp validate({:deny, _reason} = decision), do: decision

  defp validate(_other) do
    emit_failure(:decider_bad_return)
    {:deny, :decider_bad_return}
  end

  defp default_decision(%NetworkPolicy{default: :allow}), do: :allow
  defp default_decision(%NetworkPolicy{default: :deny}), do: {:deny, :default_deny}

  defp emit_failure(reason) do
    :telemetry.execute(
      [:condukt, :sandbox, :network_policy, :decider_failure],
      %{count: 1},
      %{reason: reason}
    )
  end

  defp emit_failure_and_default(reason, policy) do
    emit_failure(reason)
    default_decision(policy)
  end
end
