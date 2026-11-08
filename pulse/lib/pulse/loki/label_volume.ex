defmodule Pulse.Loki.LabelVolume do
  @moduledoc """
  Bounded label-name volumes for Loki's `aggregateBy=labels` mode.

  Counts actual line bytes once for each stream label, independently of its
  value. Range requests rank names separately in each epoch-aligned bucket;
  no logs or per-value series are retained in the accumulator.
  """

  alias Pulse.LogQL.AST
  alias Pulse.LogQL.Evaluator
  alias Pulse.Loki.Discovery
  alias Pulse.PromQL.Evaluator, as: Budget
  alias Pulse.QueryRunner

  @max_names 5000
  @max_name_bytes 1_048_576

  def query(tenant, %AST.LogQuery{stages: []} = query, times, targets, limit, step) do
    QueryRunner.run(
      tenant,
      :logql,
      fn deadline ->
        Process.put(:query_deadline_ms, deadline)
        Process.put(:promql_deadline_ms, deadline)
        Process.put(:promql_budget, %{work: 0, log_samples: 0, materialized: 0, points: 0})
        collect(tenant, query, times, targets, limit, step)
      end,
      times
    )
  end

  def query(_tenant, _query, _times, _targets, _limit, _step), do: {:error, {:invalid_query_parameter, "query"}}

  defp collect(tenant, query, times, targets, limit, step) do
    opts = %{start_ts_ns: times.start_ns, end_ts_ns: times.end_ns}
    matched_names = MapSet.new(query.selector.matchers, & &1.name)
    required = Enum.reject(targets || [], &MapSet.member?(matched_names, &1))

    observe = fn entry, record, acc ->
      Budget.charge(:log_samples, 1)
      labels = Discovery.labels(record)
      Budget.charge(:work, map_size(labels))
      names = if targets, do: Map.take(labels, targets), else: labels

      if Enum.all?(required, &Map.has_key?(labels, &1)) do
        bucket = bucket(entry.timestamp_ns, times, step)
        bytes = byte_size(entry.line)

        names |> Map.delete("__loki_tenant__") |> Map.keys() |> Enum.reduce(acc, &add(&2, &1, bucket, bytes))
      else
        acc
      end
    end

    with {:ok, {volumes, _names, _bytes}} <- Evaluator.fold_log(query, tenant, opts, {%{}, %{}, 0}, observe) do
      {:ok, finish(volumes, limit, step)}
    end
  catch
    {:promql_error, reason} -> {:error, reason}
  end

  # Keep source nanosecond precision, including start/end. Internal boundaries
  # belong to the next bucket; the final end is inclusive. Loki timestamps
  # nonfinal buckets one millisecond before the next epoch boundary.
  defp bucket(_ts, times, nil), do: times.end_ns

  defp bucket(ts, times, step) do
    ts = if ts == times.end_ns and ts > times.start_ns, do: ts - 1, else: ts
    boundary = (Integer.floor_div(ts, step) + 1) * step
    if boundary >= times.end_ns, do: times.end_ns, else: boundary - 1_000_000
  end

  defp add({volumes, names, name_bytes}, name, bucket, bytes) do
    {name, names, name_bytes} =
      case Map.fetch(names, name) do
        {:ok, canonical} ->
          {canonical, names, name_bytes}

        :error ->
          if map_size(names) >= @max_names or name_bytes + byte_size(name) > @max_name_bytes,
            do: throw({:promql_error, :query_result_limit})

          name = :binary.copy(name)
          {name, Map.put(names, name, name), name_bytes + byte_size(name)}
      end

    key = {bucket, name}
    if not Map.has_key?(volumes, key), do: Budget.charge(:materialized, 1)
    {Map.update(volumes, key, bytes, &(&1 + bytes)), names, name_bytes}
  end

  defp finish(volumes, limit, step) do
    series =
      volumes
      |> Enum.group_by(fn {{bucket, _name}, _bytes} -> bucket end)
      |> Enum.flat_map(fn {bucket, entries} ->
        entries
        |> Enum.sort_by(fn {{_, name}, bytes} -> {-bytes, name} end)
        |> Enum.take(limit)
        |> Enum.map(fn {{_, name}, bytes} -> {name, {bucket, bytes}} end)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {name, samples} -> {name, Enum.sort(samples)} end)
      |> Enum.sort_by(fn {name, [{_, bytes} | _]} -> {-bytes, name} end)

    Budget.charge(:points, Enum.reduce(series, 0, fn {_, samples}, n -> n + length(samples) end))

    if step do
      {:matrix, Enum.map(series, fn {name, samples} -> {%{name => ""}, samples} end)}
    else
      {:vector, Enum.map(series, fn {name, [sample]} -> {%{name => ""}, sample} end)}
    end
  end
end
