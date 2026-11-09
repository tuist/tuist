defmodule Pulse.Exemplars do
  @moduledoc """
  Prometheus' `/api/v1/query_exemplars`: the exemplars of every series the
  selectors of a PromQL query select, with timestamps in `[start, end]`.

  Exemplars are stored on the sample of their series nearest to them in time
  (`Pulse.Record.MetricSample`), so samples up to `@slack_ns` outside the
  window are read and their exemplars filtered by their own timestamps. Like
  Prometheus, the query's functions and operators are ignored: only its
  selectors matter. Reads run under the query runner's bounds and deadline.
  """

  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.Parser
  alias Pulse.QueryRunner
  alias Pulse.Storage

  @slack_ns 300_000_000_000

  @doc "Exemplars grouped by series, in Prometheus' response shape."
  @spec query(String.t(), String.t(), integer(), integer()) :: {:ok, [map()]} | {:error, term()}
  def query(query, tenant, start_ns, end_ns) when start_ns <= end_ns do
    with {:ok, ast} <- Parser.parse(query) do
      selectors = ast |> selectors([]) |> Enum.uniq()
      QueryRunner.run(tenant, :promql, &collect(selectors, tenant, start_ns, end_ns, &1))
    end
  end

  def query(_query, _tenant, _start_ns, _end_ns), do: {:error, :invalid_time_range}

  defp collect(selectors, tenant, start_ns, end_ns, deadline) do
    opts =
      QueryRunner.storage_opts(deadline) ++
        [start_ts: start_ns - @slack_ns, end_ts: end_ns + @slack_ns, exemplars: true]

    Enum.reduce_while(selectors, {:ok, []}, fn matchers, {:ok, acc} ->
      case Storage.query(:metrics, tenant, Keyword.put(opts, :matchers, Enum.map(matchers, &anchored/1))) do
        {:ok, samples} -> {:cont, {:ok, samples ++ acc}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, samples} -> {:ok, group(samples, start_ns, end_ns)}
      error -> error
    end
  end

  defp group(samples, start_ns, end_ns) do
    samples
    |> Enum.group_by(& &1.labels, & &1.exemplars)
    |> Enum.flat_map(fn {labels, lists} ->
      exemplars =
        lists
        |> List.flatten()
        |> Enum.filter(&(&1.timestamp_ns >= start_ns and &1.timestamp_ns <= end_ns))
        |> Enum.uniq()
        |> Enum.sort_by(& &1.timestamp_ns)

      if exemplars == [], do: [], else: [%{"seriesLabels" => labels, "exemplars" => Enum.map(exemplars, &render/1)}]
    end)
    |> Enum.sort_by(& &1["seriesLabels"])
  end

  defp render(exemplar) do
    %{
      "labels" => exemplar.labels,
      "value" => Evaluator.format_value(exemplar.value),
      "timestamp" => exemplar.timestamp_ns / 1_000_000_000
    }
  end

  # Every selector in the query, instant or range, anywhere in the tree.
  defp selectors({:selector, matchers, _offset}, acc), do: [matchers | acc]
  defp selectors({:range, matchers, _window, _offset}, acc), do: [matchers | acc]
  defp selectors(node, acc) when is_tuple(node), do: node |> Tuple.to_list() |> selectors(acc)
  defp selectors(nodes, acc) when is_list(nodes), do: Enum.reduce(nodes, acc, &selectors/2)
  defp selectors(_leaf, acc), do: acc

  # PromQL regex matchers are fully anchored, as the evaluator applies them.
  defp anchored({name, op, pattern}) when op in [:re, :nre], do: {name, op, Pulse.QueryRegex.anchor(pattern)}
  defp anchored(matcher), do: matcher
end
