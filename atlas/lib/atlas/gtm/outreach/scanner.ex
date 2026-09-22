defmodule Atlas.GTM.Outreach.Scanner do
  @moduledoc false

  alias Atlas.GTM
  alias Atlas.GTM.Outreach.BraveSearch
  alias Atlas.GTM.Outreach.GitHubSearch
  alias Atlas.GTM.Outreach.Topics
  alias Atlas.GTM.SignalQuery

  def default_queries, do: Topics.curated_queries()

  def run(opts \\ []) do
    with {:ok, _queries} <- GTM.ensure_research_signal_queries(Keyword.put_new(opts, :agent?, true)) do
      queries = GTM.list_signal_queries(enabled?: true)

      queries
      |> Task.async_stream(&run_query(&1, opts), max_concurrency: 4, timeout: :infinity)
      |> Enum.reduce(%{queries: 0, skipped: 0, signals: 0, errors: []}, &merge_result/2)
      |> then(&{:ok, &1})
    end
  end

  def run_query(%SignalQuery{} = query, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    if due_query?(query, opts, now) do
      do_run_query(query, opts, now)
    else
      %{queries: 0, skipped: 1, signals: 0, errors: []}
    end
  end

  defp do_run_query(%SignalQuery{} = query, opts, now) do
    result =
      case query.source do
        "brave" -> BraveSearch.search(query.query, Keyword.put(opts, :count, query.result_limit))
        "github" -> GitHubSearch.search(query.query, Keyword.put(opts, :count, query.result_limit))
        source -> {:error, {:unsupported_signal_source, source}}
      end

    _ = GTM.mark_signal_query_run(query, now)

    case result do
      {:ok, signal_attrs} ->
        recorded =
          signal_attrs
          |> Enum.map(&GTM.record_gtm_signal(Map.put(&1, :query_id, query.id), prepare_high_score?: true))
          |> Enum.filter(&match?({:ok, _signal}, &1))

        %{queries: 1, skipped: 0, signals: length(recorded), errors: []}

      {:error, reason} ->
        %{
          queries: 1,
          skipped: 0,
          signals: 0,
          errors: [%{query: query.name, source: query.source, reason: inspect(reason)}]
        }
    end
  end

  defp merge_result({:ok, result}, acc) do
    %{
      queries: acc.queries + result.queries,
      skipped: acc.skipped + result.skipped,
      signals: acc.signals + result.signals,
      errors: acc.errors ++ result.errors
    }
  end

  defp merge_result({:exit, reason}, acc) do
    %{acc | errors: acc.errors ++ [%{query: "unknown", reason: inspect(reason)}]}
  end

  defp due_query?(query, opts, now) do
    if Keyword.get(opts, :force?, false) or Keyword.get(opts, :force, false) do
      true
    else
      due_query_by_last_run?(query, opts, now)
    end
  end

  defp due_query_by_last_run?(%SignalQuery{last_run_at: nil}, _opts, _now), do: true

  defp due_query_by_last_run?(%SignalQuery{last_run_at: %DateTime{} = last_run_at}, opts, %DateTime{} = now) do
    DateTime.diff(now, last_run_at, :second) >= query_cooldown_seconds(opts)
  end

  defp query_cooldown_seconds(opts) do
    Keyword.get(opts, :query_cooldown_seconds) ||
      :atlas
      |> Application.get_env(:gtm_outreach, [])
      |> Keyword.get(:query_cooldown_seconds, 86_400)
  end
end
