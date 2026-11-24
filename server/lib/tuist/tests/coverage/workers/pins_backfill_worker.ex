defmodule Tuist.Tests.Coverage.Workers.PinsBackfillWorker do
  @moduledoc """
  Pins the shard reports of runs whose totals were published before
  `coverage_runs` carried `report_shards` and `report_inserted_at`, so
  readers can take every run's reports from its pins alone
  (`Tuist.Tests.Coverage.report_files_for_runs/3`). Queued once by the
  PostgreSQL migration of the release that writes the pins, it runs a second
  pass an hour later for the totals that servers still on the previous
  release published meanwhile.

  A run's pins are each shard's newest report in `coverage_run_files`, the
  report readers took before the pins. The run's newest totals row is
  copied with them, one version above, keeping its `inserted_at` and so its
  time-to-live. The check that the newest row pins nothing is part of the
  insert, so a run a newer report pinned meanwhile is left alone, and a pass
  that failed halfway or ran twice pins nothing twice. A run without run
  rows (it listed no file, or they expired) has nothing to pin and is
  skipped. Like `Tuist.Tests.Coverage.Workers.TotalsWorker`, it inserts with
  a quorum of every replica.
  """
  # Its own queue, which servers still on the release before it don't run,
  # so they never claim a job they have no worker for.
  use Oban.Worker, queue: :coverage_pins_backfill, max_attempts: 20

  alias Tuist.ClickHouse.Inserts
  alias Tuist.IngestRepo
  alias Tuist.Tests.CoverageRun

  require Logger

  @runs_per_insert 1_000
  @second_pass_delay_seconds 3600
  @quorum_timeout_ms 60_000
  # Bounds both queries whatever the table holds: they group by run and
  # shard, so one thread and a modest ceiling are enough.
  @settings [max_threads: 1, max_insert_threads: 1, max_block_size: 65_536, max_memory_usage: 256 * 1024 * 1024]
  @copied_fields CoverageRun.__schema__(:fields) -- [:version, :report_shards, :report_inserted_at]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    pinned =
      unpinned_runs()
      |> Enum.group_by(&hd/1, &List.last/1)
      |> Enum.flat_map(fn {project_id, run_ids} ->
        run_ids |> Enum.chunk_every(@runs_per_insert) |> Enum.map(&{project_id, &1})
      end)
      |> Enum.reduce(0, fn {project_id, run_ids}, total -> total + pin(project_id, run_ids) end)

    Logger.info("Coverage totals: pinned the shard reports of #{pinned} runs")

    if Map.get(args, "pass", 1) == 1 do
      %{pass: 2} |> new(schedule_in: @second_pass_delay_seconds) |> Oban.insert!()
    end

    :ok
  end

  # Runs whose newest totals pin nothing though their reports listed files.
  defp unpinned_runs do
    """
    SELECT project_id, toString(test_run_id) FROM coverage_runs
    GROUP BY project_id, test_run_id
    HAVING empty(argMax(report_shards, version)) AND argMax(files, version) > 0
    ORDER BY project_id, test_run_id
    """
    |> IngestRepo.query!([], settings: @settings, timeout: 120_000)
    |> Map.fetch!(:rows)
  end

  defp pin(project_id, run_ids) do
    replicas = Inserts.replicas()

    settings =
      if replicas > 1,
        do: @settings ++ [insert_quorum: replicas, insert_quorum_timeout: @quorum_timeout_ms],
        else: @settings

    %{num_rows: pinned} =
      IngestRepo.query!(pin_sql(), %{"project_id" => project_id, "run_ids" => run_ids},
        settings: settings,
        timeout: 120_000
      )

    pinned
  end

  defp pin_sql do
    newest = @copied_fields -- [:project_id, :test_run_id]

    """
    INSERT INTO coverage_runs (project_id, test_run_id, #{Enum.join(newest, ", ")}, version, report_shards,
      report_inserted_at)
    SELECT r.project_id, r.test_run_id, #{Enum.map_join(newest, ", ", &"r.newest_#{&1}")}, r.newest_version + 1,
      arrayMap(p -> p.1, p.reports), arrayMap(p -> p.2, p.reports)
    FROM (
      SELECT project_id, test_run_id, #{Enum.map_join(newest, ", ", &"argMax(#{&1}, version) AS newest_#{&1}")},
        max(version) AS newest_version
      FROM coverage_runs
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
      GROUP BY project_id, test_run_id
      HAVING empty(argMax(report_shards, version))
    ) AS r
    INNER JOIN (
      SELECT test_run_id, arraySort(groupArray((shard_index, newest_report))) AS reports
      FROM (
        SELECT test_run_id, shard_index, max(inserted_at) AS newest_report FROM coverage_run_files
        WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
        GROUP BY test_run_id, shard_index
      )
      GROUP BY test_run_id
    ) AS p ON p.test_run_id = r.test_run_id
    """
  end
end
