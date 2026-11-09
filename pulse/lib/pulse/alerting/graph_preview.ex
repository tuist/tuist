defmodule Pulse.Alerting.GraphPreview do
  @moduledoc "Read-only, explicitly bound native source previews. Never publishes Grafana lifecycle or enables imports."
  alias Pulse.Alerting.Expressions
  alias Pulse.Alerting.Principal
  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.FloatParser
  alias Pulse.PromQL.Number
  alias Pulse.Runtime

  @year_seconds 31_536_000
  @source_fields ~w(datasource editorMode exemplar expr hide instant interval intervalMs legendFormat maxDataPoints range refId format queryType timeShift)

  def bindings(bindings) when is_list(bindings) and length(bindings) <= 256 do
    ids = Enum.map(bindings, fn binding -> if is_map(binding), do: {binding["tenant"], binding["uid"]} end)

    if Enum.all?(bindings, &binding?/1) and length(Enum.uniq(ids)) == length(ids),
      do: :ok,
      else: {:error, :invalid_source_bindings}
  end

  def bindings(_), do: {:error, :invalid_source_bindings}

  defp binding?(%{"tenant" => tenant, "uid" => uid, "type" => type} = binding)
       when type in ["native_promql", "native_logql"],
       do:
         Principal.valid_id?(tenant) and Principal.valid_id?(uid) and
           Enum.sort(Map.keys(binding)) == ~w(tenant type uid)

  defp binding?(_), do: false

  def preview(original, tenant, now) do
    configured = Keyword.get(Runtime.get_env(:pulse, Pulse.Alerting, []), :source_bindings, [])

    with :ok <- bindings(configured),
         {:ok, plan} <- Expressions.compile(original),
         {:ok, queries} <- queries(original, plan.sources, tenant, now, configured) do
      Evaluator.query_batch(queries, tenant, &finish_preview(original, plan.terminal, &1, &2))
    end
  end

  defp finish_preview(original, terminal, results, deadline) do
    with {:ok, inputs} <- inputs(results),
         {:ok, graph} <- Expressions.execute(original, inputs, deadline: deadline),
         :ok <- result_budget(graph) do
      {:ok,
       %{
         "kind" => "grafana_expression_preview",
         "condition" => terminal,
         "result" => render(graph.terminal),
         "notices" => Enum.map(graph.notices, &%{"ref" => &1.ref, "dropped" => &1.dropped}),
         "executable" => false,
         "migrated" => false,
         "blockers" => [
           "grafana_lifecycle_templates_delivery_not_implemented",
           "source_residency_and_recording_freshness_unproven",
           "source_frame_conversion_and_pipeline_parity_unproven"
         ]
       }}
    end
  end

  defp queries(original, refs, tenant, now, bindings) do
    sources = Map.new(original["data"], &{&1["refId"], &1})

    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, acc} ->
      case source_query(sources[ref], tenant, now, bindings) do
        {:ok, query} -> {:cont, {:ok, [query | acc]}}
        {:error, reason} -> {:halt, {:error, {:graph_source, ref, reason}}}
      end
    end)
  end

  defp source_query(node, tenant, now, bindings) do
    uid = node["datasourceUid"]
    binding = Enum.find(bindings, &(&1["tenant"] == tenant and &1["uid"] == uid))

    with %{"type" => type} <- binding,
         model when is_map(model) <- node["model"],
         true <- Map.keys(model) -- @source_fields == [],
         true <- model["exemplar"] in [nil, false] and model["format"] in [nil, "time_series"],
         true <- model["refId"] in [nil, node["refId"]] and model["timeShift"] == nil,
         expr when is_binary(expr) <- model["expr"],
         {:ok, opts} <- source_options(type, node, model, uid, now) do
      {:ok, {node["refId"], expr, opts}}
    else
      nil -> {:error, :unbound_source}
      {:error, _} = error -> error
      _ -> {:error, :unsupported_source_query}
    end
  end

  defp source_options("native_promql", node, model, uid, now) do
    with true <- node["source_type"] in [nil, "prometheus"],
         true <- datasource?(model["datasource"], uid, "prometheus"),
         true <- model["queryType"] in [nil, "instant"],
         true <- model["instant"] == true and model["range"] in [nil, false],
         {:ok, time} <- source_time(node["relativeTimeRange"], now) do
      {:ok, %{end_ts_ns: time}}
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_source_query}
    end
  end

  defp source_options("native_logql", node, model, uid, now) do
    with true <- node["source_type"] in [nil, "loki"],
         true <- datasource?(model["datasource"], uid, "loki"),
         true <- model["instant"] in [nil, false, true],
         {:ok, opts} <- logql_options(model, node["relativeTimeRange"], now) do
      {:ok, Map.put(opts, :language, :logql)}
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_source_query}
    end
  end

  defp datasource?(nil, _, _), do: true

  defp datasource?(%{"type" => type} = source, uid, type),
    do: source["uid"] in [nil, uid] and Map.keys(source) -- ~w(type uid) == []

  defp datasource?(_, _, _), do: false

  defp logql_options(%{"queryType" => "instant"} = model, window, now) do
    with true <- model["range"] in [nil, false], {:ok, time} <- source_time(window, now) do
      {:ok, %{end_ts_ns: time}}
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_source_query}
    end
  end

  defp logql_options(%{"queryType" => "range", "intervalMs" => interval} = model, %{"from" => from} = window, now)
       when is_integer(interval) and interval > 0 and interval <= 31_536_000_000 do
    with true <- model["range"] in [nil, true],
         {:ok, finish} <- source_time(window, now),
         start = now - from * 1_000_000_000,
         true <- start >= 0 do
      {:ok, %{start_ts_ns: start, end_ts_ns: finish, step_ns: interval * 1_000_000}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_source_time}
    end
  end

  defp logql_options(_, _, _), do: {:error, :unsupported_source_query}

  defp source_time(nil, now) when is_integer(now) and now >= 0 and now <= 9_223_372_036_854_775_807, do: {:ok, now}

  defp source_time(%{"from" => from, "to" => to} = window, now)
       when is_integer(now) and is_integer(from) and is_integer(to) and to >= 0 and from <= @year_seconds do
    time = now - to * 1_000_000_000

    if map_size(window) == 2 and from >= to and time >= 0 and time <= 9_223_372_036_854_775_807,
      do: {:ok, time},
      else: {:error, :invalid_source_time}
  end

  defp source_time(_, _), do: {:error, :invalid_source_time}

  @doc false
  def inputs(results) do
    Enum.reduce_while(results, {:ok, %{}}, fn {ref, result}, {:ok, acc} ->
      case input(result) do
        {:ok, frames} -> {:cont, {:ok, Map.put(acc, ref, frames)}}
        error -> {:halt, error}
      end
    end)
  end

  defp input(%{"data" => %{"resultType" => "vector", "result" => samples}}) when is_list(samples) do
    Enum.reduce_while(samples, {:ok, []}, fn
      %{"metric" => labels, "value" => [_, value]}, {:ok, acc} ->
        case FloatParser.parse(value) do
          {:ok, value} -> {:cont, {:ok, [%{labels: labels, value: value} | acc]}}
          _ -> {:halt, {:error, :invalid_query_result}}
        end

      _, _ ->
        {:halt, {:error, :invalid_query_result}}
    end)
    |> case do
      {:ok, frames} -> {:ok, {:numbers, Enum.reverse(frames)}}
      error -> error
    end
  end

  defp input(%{"data" => %{"resultType" => "scalar", "result" => [_, value]}}) do
    case FloatParser.parse(value) do
      {:ok, value} -> {:ok, {:scalar, value}}
      _ -> {:error, :invalid_query_result}
    end
  end

  defp input({:logql, :vector, series}) when is_list(series) do
    {:ok, {:numbers, Enum.map(series, fn {labels, {_, value}} -> %{labels: labels, value: value} end)}}
  end

  defp input({:logql, :scalar, [{_, {_, value}}]}), do: {:ok, {:scalar, value}}

  defp input({:logql, :matrix, series}) when is_list(series) do
    {:ok, {:series, Enum.map(series, fn {labels, points} -> %{labels: labels, points: points} end)}}
  end

  defp input(_), do: {:error, :invalid_query_result}

  # Bound the eventual HTTP/MCP encoding before constructing response frames.
  # Every input byte can escape to at most six JSON bytes. Counting repeated
  # labels per surviving frame avoids aliasing/shared maps hiding response size.
  defp result_budget(graph) do
    base = Enum.reduce(graph.notices, 8192, fn notice, used -> used + 64 + 6 * byte_size(notice.ref) end)

    costs =
      case graph.terminal do
        {:scalar, _} -> [64]
        {:numbers, frames} -> Enum.map(frames, &(64 + label_size(&1.labels)))
        {:series, frames} -> Enum.map(frames, &(64 + label_size(&1.labels) + 96 * length(&1.points)))
      end

    if Enum.sum(costs) + base <= 1_048_576, do: :ok, else: {:error, :expression_result_limit}
  end

  defp label_size(labels),
    do: Enum.reduce(labels, 2, fn {k, v}, used -> used + 8 + 6 * (byte_size(k) + byte_size(v)) end)

  defp render({:scalar, value}), do: %{"type" => "scalar", "value" => number(value)}

  defp render({:numbers, frames}),
    do: %{"type" => "numbers", "frames" => Enum.map(frames, &%{"labels" => &1.labels, "value" => number(&1.value)})}

  defp render({:series, frames}),
    do: %{
      "type" => "series",
      "frames" =>
        Enum.map(
          frames,
          &%{"labels" => &1.labels, "points" => Enum.map(&1.points, fn {t, v} -> [Integer.to_string(t), number(v)] end)}
        )
    }

  defp number(nil), do: nil
  defp number(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])
  defp number(value), do: Number.format(value)
end
