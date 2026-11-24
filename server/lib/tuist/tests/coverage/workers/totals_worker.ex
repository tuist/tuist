defmodule Tuist.Tests.Coverage.Workers.TotalsWorker do
  @moduledoc """
  Inserts a shard report's totals into `coverage_runs` once every replica
  holds the rows they cover: the `coverage_run_files` of every shard report
  the row pins (`report_shards`, `report_inserted_at`: this report and the
  other shards' it merged) and, when it stored any, this report's evidence in
  `coverage_files`, recorded in `Tuist.ClickHouse.Inserts` under the
  report's key (`Tuist.Tests.Coverage.report_key/2`). Readers take each
  shard's rows at the pinned `inserted_at`.

  `coverage_runs` is how readers find a run's coverage, so a run shows up
  there only with all of its rows on every replica, whichever one a reader
  hits. The totals go in with a quorum of every replica, so the fold this
  queues finds them on whichever replica it reads.

  `publish/4` checks at once, which on a single server always succeeds, and
  otherwise leaves the check to this job, which snoozes until the replicas
  caught up. Past ten minutes it inserts the totals anyway, without the
  quorum, and logs the replica that lagged. A report replaced by a newer
  report of the same shard publishes nothing: the newer one's totals rank
  above it.
  """
  # Its own queue: servers still on the release before it don't run the
  # queue, so they never claim a job they have no worker for.
  use Oban.Worker, queue: :coverage_totals, max_attempts: 5

  alias Tuist.ClickHouse.Inserts
  alias Tuist.IngestRepo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.CoverageRun

  require Logger

  @snooze_seconds 5
  @give_up_seconds 600
  @quorum_timeout_ms 10_000
  @fields CoverageRun.__schema__(:fields)

  @doc """
  Inserts `run`, a `coverage_runs` row, once every replica holds the report's
  rows: now when they already do, otherwise from a job. `reported_at` is the
  `inserted_at` of the report's `coverage_run_files` rows, and `files` how
  many it wrote. The caller schedules the commit's fold as before; a job
  that inserts later schedules another.
  """
  def publish(run, shard_index, reported_at, files) do
    args = %{
      run:
        run
        |> Map.take(@fields)
        |> Map.update!(:report_inserted_at, &Enum.map(&1, fn at -> NaiveDateTime.to_iso8601(at) end)),
      shard_index: shard_index,
      reported_at: NaiveDateTime.to_iso8601(reported_at),
      files: files
    }

    published =
      try do
        (args |> JSON.encode!() |> JSON.decode!() |> sync(nil)) in [:published, :ok]
      rescue
        error ->
          Logger.warning("Deferring the coverage totals of test run #{run.test_run_id}: #{Exception.message(error)}")
          false
      end

    if not published, do: args |> new(schedule_in: @snooze_seconds) |> Oban.insert!()
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, inserted_at: enqueued_at}) do
    case sync(args, enqueued_at) do
      :published ->
        run = run(args)
        Commits.enqueue_recompute(run.project_id, run.git_commit_sha)
        :ok

      other ->
        other
    end
  end

  defp sync(%{"shard_index" => shard_index} = args, enqueued_at) do
    run = run(args)
    reported_at = micro(NaiveDateTime.from_iso8601!(args["reported_at"]))
    inserts = Inserts.by_table(Coverage.report_key(run.test_run_id, shard_index))
    files = Map.get(inserts, "coverage_run_files")
    evidence = Map.get(inserts, "coverage_files")

    # The rows to find on every replica: each pinned report's run files and
    # the evidence the shard's request stored.
    awaited =
      Enum.zip_with(run.report_shards, run.report_inserted_at, &{"files", &1, micro(&2)}) ++
        if(evidence, do: [{"evidence", shard_index, micro(evidence.rows_inserted_at)}], else: [])

    cond do
      files && micro(files.rows_inserted_at) != reported_at ->
        :ok

      synced?(run, shard_index, awaited) ->
        insert(run, quorum: Inserts.replicas())
        Inserts.mark_synced(Enum.reject([files, evidence], &is_nil/1))
        :published

      enqueued_at && DateTime.diff(DateTime.utc_now(), enqueued_at) > @give_up_seconds ->
        Logger.warning(
          "Publishing the coverage totals of test run #{run.test_run_id} (shard #{shard_index}) " <>
            "before every replica holds its rows"
        )

        insert(run, quorum: 0)
        :published

      true ->
        {:snooze, @snooze_seconds}
    end
  end

  # Every replica holds each awaited insert's rows (a shard's rows at one
  # `inserted_at`), and as many of them as the others: an insert is
  # acknowledged once the replica that took it has all of it, so replicas
  # that agree all have it, even when a large insert landed as several parts.
  defp synced?(_run, _shard_index, []), do: true

  defp synced?(run, shard_index, awaited) do
    replicas_hold?(run, shard_index, awaited)
  rescue
    # A replica that can't be reached can't be counted on either.
    error in [Ch.Error, DBConnection.ConnectionError, Mint.TransportError, Mint.HTTPError] ->
      Logger.warning("Counting the coverage rows of test run #{run.test_run_id} failed: #{Exception.message(error)}")
      false
  end

  defp replicas_hold?(run, shard_index, awaited) do
    db = Inserts.database()

    sql = """
    SELECT 'replica' AS kind, toUInt32(0) AS shard, toInt64(0) AS at, toUInt64(0) AS n
    UNION ALL
    SELECT 'files', shard_index, toUnixTimestamp64Micro(inserted_at), count() FROM #{db}.coverage_run_files
    WHERE project_id = {project_id:Int64} AND test_run_id = {test_run_id:UUID}
    GROUP BY shard_index, inserted_at
    UNION ALL
    SELECT 'evidence', shard_index, toUnixTimestamp64Micro(inserted_at), count() FROM #{db}.coverage_files
    WHERE project_id = {project_id:Int64} AND test_run_id = {test_run_id:UUID}
      AND shard_index = {shard_index:UInt32} AND scope_kind != 'run'
    GROUP BY shard_index, inserted_at
    """

    %{rows: rows} =
      IngestRepo.query!(
        Inserts.on_every_replica(sql),
        %{project_id: run.project_id, test_run_id: run.test_run_id, shard_index: shard_index}
      )

    by_replica =
      rows
      |> Enum.group_by(&hd/1, fn [_, kind, shard, at, n] -> {{kind, shard, at}, n} end)
      |> Enum.map(fn {_replica, counts} -> Map.new(counts) end)

    Enum.all?(awaited, fn insert ->
      counts = Enum.map(by_replica, &Map.get(&1, insert, 0))
      Enum.all?(counts, &(&1 > 0)) and length(Enum.uniq(counts)) == 1
    end)
  end

  defp insert(run, quorum: replicas) do
    opts =
      if replicas > 1,
        do: [settings: [insert_quorum: replicas, insert_quorum_timeout: @quorum_timeout_ms]],
        else: []

    IngestRepo.insert_all(CoverageRun, [run], opts)
  end

  defp run(%{"run" => run}) do
    run = Map.new(@fields, &{&1, Map.get(run, Atom.to_string(&1))})

    %{
      run
      | inserted_at: NaiveDateTime.from_iso8601!(run.inserted_at),
        report_shards: run.report_shards || [],
        report_inserted_at: Enum.map(run.report_inserted_at || [], &NaiveDateTime.from_iso8601!/1)
    }
  end

  defp micro(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> micro()
  defp micro(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond)
end
