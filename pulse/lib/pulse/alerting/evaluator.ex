defmodule Pulse.Alerting.Evaluator do
  @moduledoc "Bounded native single/mixed-source threshold and recording evaluation with rule-head fencing."
  alias Pulse.Alerting.GraphPreview
  alias Pulse.Alerting.{Lifecycle, Principal, Recording, Repository}
  alias Pulse.Alerting.NativeExpression
  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.Number

  @recording_kinds ["promql_recording", "promql_recording_group"]
  # Retryable conditions skip the whole tick; nothing is published or marked stale.
  @transient [
    :query_overloaded,
    :query_timeout,
    :manifest_freshness_unavailable,
    :signal_authority_missing,
    :expression_timeout
  ]

  def evaluate(principal, id, opts \\ []) do
    with :ok <- Principal.authorize(principal, "alert:evaluate"),
         :ok <- Principal.authorize(principal, "alert:read"),
         {:ok, head, etag} <- Repository.load(principal.tenant, id, opts),
         :ok <- Principal.authorize(principal, "alert:evaluate", head["classification"]),
         "active" <- head["state"],
         {:ok, snapshot} <- Repository.revision(principal.tenant, id, head["revision"], opts),
         %{"kind" => kind} = rule
         when kind in ["promql_threshold", "logql_threshold", "expression_threshold" | @recording_kinds] <-
           snapshot["rule"] do
      now =
        Keyword.get_lazy(opts, :timestamp_ns, fn ->
          period = rule["cadence_ms"] * 1_000_000
          div(System.system_time(:nanosecond), period) * period
        end)

      evaluate_cadence(principal, id, rule, {head, etag}, now, opts)
    else
      "disabled" -> {:error, :rule_disabled}
      "deleted" -> {:error, :rule_disabled}
      {:error, _} = error -> error
      _ -> {:error, :unsupported_rule}
    end
  end

  defp evaluate_cadence(principal, id, rule, {head, etag}, now, opts) do
    previous = String.to_integer(head["completed_at_ns"])
    kind = rule["kind"]
    fence = if kind in @recording_kinds, do: String.to_integer(Map.get(head, "recording_fence_ns", "-1")), else: -1

    cond do
      now <= max(previous, fence) or (previous >= 0 and now - previous < rule["cadence_ms"] * 1_000_000) ->
        {:error, :not_due}

      kind in @recording_kinds and recording_blocked?(head, opts) ->
        {:error, :recording_backlog}

      budget_skipped?(principal.tenant, id, head["revision"]["digest"], now, opts) ->
        skip(:budget)

      true ->
        evaluate_due(principal, id, rule, {head, etag}, now, opts)
    end
  end

  defp recording_blocked?(head, opts) do
    queue = Map.get(head, "recording_queue", [])
    length(queue) >= 63 or (Keyword.get(opts, :require_recording_drained, false) and queue != [])
  end

  defp evaluate_due(principal, id, rule, {head, etag}, now, opts) do
    started = System.monotonic_time(:millisecond)

    result =
      if rule["kind"] == "promql_recording_group",
        do: query_group(rule, principal.tenant, now, Map.get(head, "recording_series", []), opts),
        else: query(rule, principal.tenant, now, opts)

    if System.monotonic_time(:millisecond) - started >= rule["cadence_ms"],
      do: skip(:overrun),
      else: commit(result, principal, id, rule, head, etag, now, opts)
  end

  def preview(principal, id, opts \\ []) do
    now = Keyword.get_lazy(opts, :timestamp_ns, fn -> System.system_time(:nanosecond) end)

    with :ok <- Principal.authorize(principal, "alert:preview"),
         {:ok, current} <- Pulse.Alerting.get(principal, id, opts) do
      preview_rule(current["rule"], principal.tenant, now, opts)
    end
  end

  defp preview_rule(%{"kind" => "grafana", "original" => original}, tenant, now, _opts),
    do: GraphPreview.preview(original, tenant, now)

  defp preview_rule(%{"kind" => "promql_recording_group"} = rule, tenant, now, opts) do
    case query_group(rule, tenant, now, [], Keyword.put(opts, :query_class, :promql)) do
      {:group, outcomes} ->
        rules =
          Enum.map(outcomes, fn
            {record, {:ok, points}} -> %{"record" => record, "samples" => points}
            {record, {:error, code}} -> %{"record" => record, "error" => code}
          end)

        with {:ok, result} <- Recording.group_transition(outcomes, now, []),
             do: {:ok, %{"timestamp_ns" => Integer.to_string(now), "rules" => rules, "health" => group_health(result)}}

      {:error, _} = error ->
        error
    end
  end

  defp preview_rule(%{"kind" => kind} = rule, tenant, now, opts)
       when kind in ["promql_threshold", "logql_threshold", "expression_threshold", "promql_recording"] do
    with {:ok, samples} <- query(rule, tenant, now, Keyword.put(opts, :query_class, :promql)),
         do: preview_result(rule, samples, now)
  end

  defp preview_rule(_, _, _, _), do: {:error, :unsupported_rule}

  defp preview_result(%{"kind" => "promql_recording"} = rule, samples, now) do
    with {:ok, result} <- Recording.result(rule, samples, now),
         do: {:ok, Map.put(result, "health", if(samples == [], do: "no_data", else: "ok"))}
  end

  defp preview_result(rule, samples, now) do
    with {:ok, instances, events, health} <- Lifecycle.step(rule, %{}, samples, now),
         do: {:ok, %{"instances" => instances, "transitions" => events, "health" => health}}
  end

  defp query(rule, tenant, now, opts) do
    {default, query} =
      case rule["kind"] do
        "expression_threshold" -> {&NativeExpression.query/3, rule}
        "logql_threshold" -> {&query_logql/3, rule["query"]}
        _ -> {&Evaluator.query/3, rule["query"]}
      end

    fun = Keyword.get(opts, :query, default)

    query_opts = %{
      end_ts_ns: now,
      query_class: Keyword.get(opts, :query_class, :alerting),
      require_fresh_manifest: true,
      recorded: Keyword.get(opts, :recorded, [])
    }

    case fun.(query, tenant, query_opts) do
      {:ok, %{"data" => %{"resultType" => "vector", "result" => samples}}} -> {:ok, samples}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_query_result}
    end
  end

  # Prometheus rule-group semantics: every rule evaluates at the same `now`, in
  # order, and sees what earlier rules appended at `now` (samples and stale
  # markers) as stored data, so chained recordings never lag a tick.
  defp query_group(rule, tenant, now, previous, opts) do
    rule["rules"]
    |> Enum.reduce_while({[], []}, &group_rule(&1, &2, tenant, now, previous, opts))
    |> case do
      {:error, _} = error -> error
      {outcomes, _recorded} -> {:group, Enum.reverse(outcomes)}
    end
  end

  defp group_rule(item, {outcomes, recorded}, tenant, now, previous, opts) do
    query_rule = %{"kind" => "promql_recording", "query" => item["expr"]}

    case query(query_rule, tenant, now, Keyword.put(opts, :recorded, recorded)) do
      {:error, reason} when reason in @transient ->
        {:halt, {:error, reason}}

      {:ok, samples} ->
        case Recording.group_points(item, samples) do
          {:ok, points} ->
            recorded = recorded ++ Recording.overlay(item["record"], points, now, previous)
            {:cont, {[{item["record"], {:ok, points}} | outcomes], recorded}}

          {:error, reason} ->
            failed(item, reason, outcomes, recorded)
        end

      {:error, reason} ->
        failed(item, reason, outcomes, recorded)
    end
  end

  # A failed rule appends nothing, not even stale markers, as in Prometheus.
  defp failed(item, reason, outcomes, recorded),
    do: {:cont, {[{item["record"], {:error, error_code(reason)}} | outcomes], recorded}}

  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code({reason, _}) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(_), do: "query_error"

  defp group_health(result) do
    health = Enum.map(result["rule_health"], & &1["health"])

    cond do
      "error" in health -> "error"
      Enum.all?(health, &(&1 == "no_data")) -> "no_data"
      true -> "ok"
    end
  end

  defp query_logql(query, tenant, opts) do
    source = {"threshold", query, %{end_ts_ns: opts.end_ts_ns, language: :logql}}
    Evaluator.query_batch([source], tenant, &logql_result/2, opts)
  end

  defp logql_result(%{"threshold" => {:logql, :vector, series}}, _deadline) when length(series) <= 128 do
    samples =
      Enum.map(series, fn {labels, {time, value}} -> %{"metric" => labels, "value" => [time, sample_value(value)]} end)

    {:ok, %{"data" => %{"resultType" => "vector", "result" => samples}}}
  end

  defp logql_result(%{"threshold" => {:logql, :vector, _}}, _), do: {:error, :instance_limit}
  defp logql_result(_, _), do: {:error, :invalid_query_result}
  defp sample_value(value) when is_number(value), do: to_string(value)
  defp sample_value(value), do: Number.format(value)

  defp skip(reason) do
    Pulse.SelfMetrics.alert_evaluation_skip(reason)
    {:error, :evaluation_skipped}
  end

  defp skip_reason(:query_overloaded), do: :capacity
  defp skip_reason(reason) when reason in [:query_timeout, :expression_timeout], do: :timeout
  defp skip_reason(:manifest_freshness_unavailable), do: :freshness_unavailable
  defp skip_reason(:signal_authority_missing), do: :authority_missing
  defp skip_reason(_), do: :budget

  defp budget_skipped?(tenant, id, revision, now, opts) do
    case opts[:budget_skip_cache] do
      nil -> false
      cache -> :ets.lookup(cache, {tenant, id}) == [{{tenant, id}, revision, now}]
    end
  end

  defp remember_budget_skip(tenant, id, revision, now, reason, opts) do
    cache = opts[:budget_skip_cache]

    if cache &&
         reason in [
           :query_resource_limit,
           :query_scan_limit,
           :query_sample_limit,
           :query_work_limit,
           :query_result_limit,
           :query_intermediate_limit
         ] &&
         (:ets.member(cache, {tenant, id}) or :ets.info(cache, :size) < 10_000) do
      # Small retained identifiers must not pin a head or LIST response arena.
      :ets.insert(cache, {{:binary.copy(tenant), :binary.copy(id)}, :binary.copy(revision), now})
    end
  end

  defp commit({:error, reason}, principal, id, _rule, head, _etag, now, opts)
       when reason in [
              :query_overloaded,
              :query_timeout,
              :query_resource_limit,
              :query_scan_limit,
              :query_sample_limit,
              :query_work_limit,
              :query_result_limit,
              :query_intermediate_limit,
              :manifest_freshness_unavailable,
              :signal_authority_missing,
              :expression_timeout
            ] do
    remember_budget_skip(principal.tenant, id, head["revision"]["digest"], now, reason, opts)
    skip(skip_reason(reason))
  end

  defp commit(result, principal, id, rule, head, etag, now, opts) do
    {instances, events, health, recording} = evaluation(result, rule, head, now)

    events =
      Enum.map(
        events,
        &Map.merge(&1, %{
          "revision" => head["revision"],
          "classification" => head["classification"],
          "actor" => %{"id" => principal.id, "type" => principal.type}
        })
      )

    events =
      if health == head["health"] do
        events
      else
        events ++
          [
            %{
              "type" => "health_changed",
              "health" => health,
              "revision" => head["revision"],
              "classification" => head["classification"],
              "timestamp_ns" => Integer.to_string(now),
              "actor" => %{"id" => principal.id, "type" => principal.type}
            }
          ]
      end

    with {:ok, next} <-
           Repository.checkpoint(
             principal.tenant,
             id,
             {head, etag},
             %{
               revision: head["revision"]["digest"],
               timestamp: now,
               instances: instances,
               health: health,
               events: events,
               recording: recording
             },
             opts
           ),
         do: {:ok, response(next, principal)}
  end

  defp response(head, principal) do
    result = Map.take(head, ~w(id generation state completed_at_ns instances health))

    # A converted threshold can still carry protected recording publications.
    # Evaluating the threshold does not grant access to that retained backlog.
    case Principal.authorize(principal, "alert:read", Recording.state_classification(head)) do
      :ok -> Map.put(result, "recording_pending", length(Map.get(head, "recording_queue", [])))
      {:error, _} -> result
    end
  end

  defp evaluation({:group, outcomes}, _rule, head, now) do
    case Recording.group_transition(outcomes, now, Map.get(head, "recording_series", [])) do
      {:ok, result} -> {%{}, [], group_health(result), result}
      {:error, _} -> {head["instances"], [], "error", nil}
    end
  end

  defp evaluation({:ok, samples}, %{"kind" => "promql_recording"} = rule, head, now) do
    case Recording.transition(rule, samples, now, Map.get(head, "recording_series", [])) do
      {:ok, result} -> {%{}, [], if(samples == [], do: "no_data", else: "ok"), result}
      {:error, _} -> {head["instances"], [], "error", nil}
    end
  end

  defp evaluation({:ok, samples}, rule, head, now) do
    case Lifecycle.step(rule, head["instances"], samples, now) do
      {:ok, instances, events, health} -> {instances, events, health, nil}
      {:error, _} -> {head["instances"], [], "error", nil}
    end
  end

  defp evaluation({:error, _}, _rule, head, _now), do: {head["instances"], [], "error", nil}
end
