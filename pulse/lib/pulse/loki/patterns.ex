defmodule Pulse.Loki.Patterns do
  @moduledoc """
  Log patterns for Loki's `/loki/api/v1/patterns`, which Grafana's Logs
  Drilldown shows and turns into `|>` / `!>` filters.

  Pulse has no pattern ingester: patterns are mined when queried, from every
  line the query selects in the window, by the native Drain miner in
  `pulse_codec` (`patterns.rs`), with line counts per `step`. Stored segments
  stream straight into the miner without becoming Erlang terms when the query
  is a selector with optional substring or regex line filters and the storage
  adapter supports native scans. Other queries, adapters, and scans that
  answer `:fallback` fold their lines through the LogQL evaluator into the
  same miner. Query budgets bound the lines read.
  """

  alias Pulse.Codec.NIF
  alias Pulse.LogQL.AST
  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.QueryValidation
  alias Pulse.QueryRunner
  alias Pulse.Storage

  @batch 1024

  @type window :: %{start_ns: integer(), end_ns: integer(), step_ns: pos_integer()}

  @doc "`{:ok, [{pattern, [{bucket_start_ns, count}]}]}`, most frequent first."
  @spec query(String.t(), AST.LogQuery.t(), window()) ::
          {:ok, [{binary(), [{integer(), pos_integer()}]}]} | {:error, term()}
  def query(tenant, %AST.LogQuery{} = query, window) do
    opts = Map.merge(Map.take(window, [:timeout_ms]), %{start_ts_ns: window.start_ns, end_ts_ns: window.end_ns})

    QueryRunner.run(
      tenant,
      :logql,
      fn deadline ->
        Process.put(:query_deadline_ms, deadline)
        with :ok <- QueryValidation.validate(query), do: mine(tenant, query, opts, window)
      end,
      opts
    )
  end

  defp mine(tenant, query, opts, window) do
    case native(tenant, query, opts, window) do
      :fallback -> folded(tenant, query, opts, window)
      result -> result
    end
  end

  defp native(tenant, query, opts, window) do
    with true <- Storage.native_log_metric?(),
         {storage_opts, []} <- Evaluator.push_down(query, opts) do
      scan = NIF.log_pattern_scan_new(window.start_ns, window.step_ns)

      case Storage.log_metric_scan(tenant, storage_opts, scan) do
        {:ok, _counts} -> NIF.log_pattern_finish(scan)
        {:error, :native_fallback} -> :fallback
        {:error, _} = error -> error
      end
    else
      _ -> :fallback
    end
  end

  defp folded(tenant, query, opts, window) do
    scan = NIF.log_pattern_scan_new(window.start_ns, window.step_ns)
    feed = &(:ok = NIF.log_pattern_observe(scan, &1))

    collect = fn entry, _record, {lines, n} ->
      lines = [{entry.timestamp_ns || 0, entry.line} | lines]

      if n + 1 >= @batch do
        feed.(Enum.reverse(lines))
        {[], 0}
      else
        {lines, n + 1}
      end
    end

    with {:ok, {rest, _n}} <- Evaluator.fold_log(query, tenant, opts, {[], 0}, collect) do
      feed.(Enum.reverse(rest))
      NIF.log_pattern_finish(scan)
    end
  end
end
