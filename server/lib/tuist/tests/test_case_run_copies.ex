defmodule Tuist.Tests.TestCaseRunCopies do
  @moduledoc """
  Fills the partitioned `test_case_runs` copies with the rows reported before
  their materialized views existed.

  Each copy takes the rows its retention keeps, read one source month at a
  time, so every statement prunes `test_case_runs` to a single partition. The
  rows go through the view's own `SELECT`, so a copy holds exactly what the
  view would have written. The copies are ReplacingMergeTree, so running a copy
  again, or rows the view wrote as well, collapse on merge.
  """
  alias Tuist.IngestRepo

  require Logger

  @retention_days %{
    "test_case_runs_by_inserted_at_v2" => 30,
    "test_case_runs_by_commit_v2" => 30,
    "test_case_runs_by_test_run_v2" => 90,
    "test_case_runs_by_shard_id_v2" => 90,
    "test_case_runs_by_project_v2" => 90
  }

  def tables, do: Map.keys(@retention_days)

  @doc """
  Copies into `table` the source rows inserted within its retention and before
  `:until`, which defaults to when the table's view was created. Returns the
  `{from, to}` ranges copied, oldest first.
  """
  def backfill(table, opts \\ []) do
    days = Map.fetch!(@retention_days, table)
    {view_select, view_created_at} = view(table)
    until = Keyword.get(opts, :until, view_created_at)
    columns = Enum.join(columns(table), ", ")

    for {from, to} <- month_ranges(NaiveDateTime.add(until, -days, :day), until) do
      IngestRepo.query!(
        """
        INSERT INTO #{table} (#{columns})
        SELECT #{columns} FROM (#{view_select})
        WHERE inserted_at >= {from:DateTime64(6)} AND inserted_at < {to:DateTime64(6)}
        """,
        %{from: from, to: to},
        timeout: :infinity
      )

      Logger.info("#{table}: copied the rows inserted from #{from} to #{to}")
      {from, to}
    end
  end

  defp month_ranges(from, to) do
    from
    |> month_start()
    |> Stream.iterate(&next_month/1)
    |> Stream.take_while(&NaiveDateTime.before?(&1, to))
    |> Enum.map(&{Enum.max([from, &1], NaiveDateTime), Enum.min([to, next_month(&1)], NaiveDateTime)})
  end

  defp month_start(datetime) do
    datetime |> NaiveDateTime.to_date() |> Date.beginning_of_month() |> NaiveDateTime.new!(~T[00:00:00])
  end

  defp next_month(month_start) do
    month_start |> NaiveDateTime.to_date() |> Date.end_of_month() |> Date.add(1) |> NaiveDateTime.new!(~T[00:00:00])
  end

  defp view(table) do
    %{rows: [[view_select, created_at]]} =
      IngestRepo.query!(
        """
        SELECT as_select, toString(metadata_modification_time)
        FROM system.tables
        WHERE database = currentDatabase() AND name = {view:String}
        """,
        %{view: "#{table}_mv"}
      )

    {view_select, NaiveDateTime.from_iso8601!(created_at)}
  end

  defp columns(table) do
    %{rows: rows} =
      IngestRepo.query!(
        """
        SELECT name FROM system.columns
        WHERE database = currentDatabase() AND table = {table:String}
        ORDER BY position
        """,
        %{table: table}
      )

    List.flatten(rows)
  end
end
