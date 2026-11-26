defmodule Tuist.Tests.Coverage.RunInputs do
  @moduledoc """
  What a commit's fold (`Tuist.Tests.Coverage.Commits.recompute/3`) reads of
  its runs besides their coverage, and the gate that holds the fold until
  every replica has it.

  The fold finds a run through its coverage totals, which
  `Tuist.Tests.Coverage.Workers.TotalsWorker` inserts only once every replica
  holds the run's coverage. The rest of what it reads of the run reaches
  ClickHouse on its own path and replicates on its own time: the run's
  `test_runs` row, its `test_case_runs` (by which test selection knows the
  run was processed) and the `xcode_targets` its command event reported
  (what selective testing skipped, what came from the binary cache). A fold
  reading a replica that lacks some of them still counts the run, and what
  it derives from half the run stays: a snapshot that left out the run's
  tests while the run became a carry source is never rewritten, since a
  snapshot is identified by its runs.

  So each of those inserts is recorded in `Tuist.ClickHouse.Inserts` under
  the run's commit, with how many rows to find: the run's report declares
  its rows before it publishes its coverage (`declare/3`) and records them
  once written (`written/4`), and its command event, which usually lands
  after the run, records its own (`event_written/3`), under the commit once
  the fold derives anything from its targets. The commit's fold
  first counts every insert of the commit not seen synced yet on every
  replica (`status/2`), and waits while one is still being written or a
  replica lacks its rows. An insert recorded more than ten minutes ago is
  no longer waited for, since its writer failed or a replica is stuck: the
  fold goes ahead without it, publishes the commit's figure as a lower bound
  (`run_data_unavailable`) and writes nothing derived from the run's tests,
  and the commit is folded once more ten minutes later in case it arrived.
  """
  import Ecto.Query

  alias Tuist.ClickHouse.Insert
  alias Tuist.ClickHouse.Inserts
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Test

  require Logger

  @give_up_seconds 600
  @clock_margin_seconds 30
  @poll_ms 500

  @doc """
  Declares the `test_runs` and `test_case_runs` rows a run's report is about
  to write for its shard, when the run reported coverage for a commit, so no
  fold counts the run before they are on every replica. Returns what
  `written/4` takes, nil for a run no fold waits for.
  """
  def declare(%Test{git_commit_sha: sha} = test, shard_index, coverage) do
    if not is_nil(coverage) and is_binary(sha) and sha != "" and test.submission_auth != "network_trusted" and
         test.reporting_version != 1 and Coverage.enabled_for_project?(test.project_id) do
      run = %{project_id: test.project_id, sha: sha, key: Coverage.report_key(test.id, shard_index)}
      now = NaiveDateTime.utc_now()

      if Enum.all?(["test_runs", "test_case_runs"], &(record(&1, run.key, run.project_id, now, sha: sha) == :ok)) do
        attach_events(test.project_id, test.id, sha)
        run
      end
    end
  end

  @doc """
  Records that the declared rows of `table` were written: `rows` of them,
  with `inserted_at` at or after `inserted_at` (`test_runs`: that version, or
  a later shard's).
  """
  def written(nil, _table, _inserted_at, _rows), do: :ok

  def written(run, table, inserted_at, rows),
    do: record(table, run.key, run.project_id, inserted_at, sha: run.sha, rows: rows)

  @doc """
  Records the command event of a run and the targets its graph stored
  (`Tuist.Xcode.create_xcode_graph/1`), when the fold of the run's commit
  derives something from them: the targets selective testing skipped or the
  binary cache provided (`hit?`, a run that skipped every target included),
  or any target of a run that reported coverage, whose test map records the
  hash each target ran under. Any other event's run has measured nothing so
  far, as one not set up to collect coverage never does, so a fold reads
  none of its targets but hits and may never run for its commit to count
  them: its inserts are recorded under the run and no commit, and join the
  commit once a report of the run declares its rows (`declare/3`), which a
  later shard or the processing of an uploaded bundle can do after the
  event landed. Each side writes before it reads the other's rows, so
  whichever comes second finds the first.
  """
  def event_written(
        %{test_run_id: run_id, git_commit_sha: sha} = event,
        %{targets: targets, inserted_at: inserted_at},
        hit?
      )
      when is_binary(run_id) and run_id != "" and is_binary(sha) and sha != "" do
    if Coverage.enabled_for_project?(event.project_id) do
      key = to_string(event.id)
      commit = if hit?, do: sha
      opts = [sha: commit, test_run_id: run_id]

      with :ok <- record("command_events", key, event.project_id, event.created_at, [rows: 1] ++ opts),
           :ok <- record("xcode_targets", key, event.project_id, inserted_at, [rows: targets] ++ opts),
           true <- is_nil(commit) and report_declared?(event.project_id, sha, run_id),
           do: attach_events(event.project_id, run_id, sha)
    end

    :ok
  end

  def event_written(_event, _graph, _hit?), do: :ok

  # Whether a shard report of the run declared its rows (`declare/3`).
  defp report_declared?(project_id, sha, run_id) do
    Repo.exists?(
      from(i in Insert,
        where:
          i.project_id == ^project_id and i.git_commit_sha == ^sha and i.clickhouse_table == "test_runs" and
            like(i.key, ^"#{run_id}/%")
      )
    )
  end

  # Puts the run's command event inserts waiting for its report under the
  # commit, as of when they were recorded: their rows were written then.
  defp attach_events(project_id, run_id, sha) do
    Repo.update_all(
      from(i in Insert,
        where: i.project_id == ^project_id and i.test_run_id == ^run_id and is_nil(i.git_commit_sha)
      ),
      set: [git_commit_sha: sha]
    )

    :ok
  rescue
    error ->
      Logger.warning("Attaching the command events of run #{run_id} to commit #{sha} failed: #{Exception.message(error)}")
      :error
  end

  # A record that fails costs only the wait: the fold goes ahead without it,
  # as it did before the gate, rather than the data it describes being lost.
  defp record(table, key, project_id, inserted_at, opts) do
    Inserts.record(table, key, project_id, inserted_at, opts)
  rescue
    error ->
      Logger.warning("Recording the #{table} insert #{key} for its commit's fold failed: #{Exception.message(error)}")
      :error
  end

  @doc """
  Whether the commit's fold can read every run input recorded for it:
  `:ready` once each is on every replica (each marked synced then), `:wait`
  while one is still being written or a replica lacks its rows, and
  `{:incomplete, missing}` once only inputs recorded too long ago to wait
  for are missing. A fold then reads part of a run, so its figure is only a
  lower bound (`Tuist.Tests.Coverage.Commits.recompute/3`'s `incomplete:`).
  Inputs found are marked synced either way, and missing ones are counted
  again by every later fold until they're found or pruned.
  """
  def status(project_id, sha) do
    inserts =
      Repo.all(from(i in Insert, where: i.project_id == ^project_id and i.git_commit_sha == ^sha and is_nil(i.synced_at)))

    # Recorded without rows: still being written. Recorded with none: nothing to find.
    {writing, recorded} = Enum.split_with(inserts, &is_nil(&1.row_count))
    {empty, counted} = Enum.split_with(recorded, &(&1.row_count == 0))
    found = empty ++ found(project_id, sha, counted)
    missing = Enum.reject(inserts, &(&1 in found))
    Inserts.mark_synced(found)

    cond do
      missing == [] ->
        :ready

      Enum.all?(missing, &expired?/1) ->
        for insert <- missing do
          Logger.warning(
            "Folding commit #{sha} of project #{project_id} as incomplete: not every replica holds " <>
              "#{insert.clickhouse_table} #{insert.key}" <> if(insert in writing, do: ", never written", else: "")
          )
        end

        {:incomplete, missing}

      true ->
        :wait
    end
  end

  @doc """
  When to fold the commit once more after a fold that went ahead without
  `missing` (`status/2`), in seconds: once, while they're younger than twice
  the wait, so the fold reads them if they arrived late; nil after that.
  """
  def follow_up_in(missing) do
    if Enum.all?(missing, &(age(&1) < 2 * @give_up_seconds)), do: @give_up_seconds
  end

  @doc """
  Waits up to `timeout_ms` for `status/2` to stop being `:wait`, for a fold
  that runs where it was asked for rather than in a job, and returns it.
  """
  def await(project_id, sha, timeout_ms) do
    case status(project_id, sha) do
      :wait when timeout_ms > 0 ->
        Process.sleep(@poll_ms)
        await(project_id, sha, timeout_ms - @poll_ms)

      status ->
        status
    end
  end

  @doc """
  The time to pass `declared_since?/3` for a gate about to be checked: now,
  less a margin for the clocks of the nodes that record the inputs.
  """
  def gated_at, do: DateTime.add(DateTime.utc_now(), -@clock_margin_seconds, :second)

  @doc """
  Whether a run input of the commit was recorded at or after `since` and no
  gate has seen it on every replica: a run's report declared after the gate
  was checked, which the fold may have read part of.
  """
  def declared_since?(project_id, sha, since) do
    Repo.exists?(
      from(i in Insert,
        where:
          i.project_id == ^project_id and i.git_commit_sha == ^sha and is_nil(i.synced_at) and i.inserted_at >= ^since
      )
    )
  end

  defp expired?(insert), do: age(insert) > @give_up_seconds
  defp age(insert), do: DateTime.diff(DateTime.utc_now(), insert.inserted_at)

  # The inserts every replica holds the rows of.
  defp found(_project_id, _sha, []), do: []

  defp found(project_id, sha, inserts) do
    {sql, params} = count_query(project_id, inserts)
    %{rows: rows} = IngestRepo.query!(Inserts.on_every_replica(sql), params)

    by_replica =
      rows
      |> Enum.group_by(&hd/1, fn [_replica, kind, id, part, n] -> {{kind, id, part}, n} end)
      |> Enum.map(fn {_replica, counts} -> Map.new(counts) end)

    Enum.filter(inserts, fn insert ->
      found = expected(insert)
      Enum.all?(by_replica, &(Map.get(&1, found, 0) >= at_least(insert)))
    end)
  rescue
    # A replica that can't be reached can't be counted on either.
    error in [Ch.Error, DBConnection.ConnectionError, Mint.TransportError, Mint.HTTPError] ->
      Logger.warning("Counting the run inputs of commit #{sha} failed: #{Exception.message(error)}")
      []
  end

  # What the count query must find for the insert on each replica: its rows,
  # or, for a run's row, its version or a newer one. Every shard rewrites the
  # run's one `test_runs` row, and a merge keeps only the newest version, so
  # an earlier shard's version can be gone once a later one is stored.
  defp at_least(%Insert{clickhouse_table: "test_runs"} = insert), do: micro(insert.rows_inserted_at)
  defp at_least(%Insert{row_count: rows}), do: rows

  # Where each insert's rows are counted, as the count query groups them.
  defp expected(%Insert{clickhouse_table: "test_runs", key: key}), do: {"test_runs", run_id(key), 0}

  defp expected(%Insert{clickhouse_table: "test_case_runs", key: key}) do
    [run_id, shard] = String.split(key, "/")
    {"test_case_runs", run_id, String.to_integer(shard)}
  end

  defp expected(%Insert{clickhouse_table: "command_events", key: key}), do: {"command_events", key, 0}

  defp expected(%Insert{clickhouse_table: "xcode_targets", key: key} = insert),
    do: {"xcode_targets", key, DateTime.to_unix(insert.rows_inserted_at)}

  # One count per table, over the keys its sorting key or projection reaches:
  # a run's newest `test_runs` version by id, its test case runs by run and shard
  # (by distinct id, since a run's flaky flag rewrites some), a command event
  # by id, and its targets by event and the `inserted_at` they share.
  defp count_query(project_id, inserts) do
    db = Inserts.database()
    by_table = Enum.group_by(inserts, & &1.clickhouse_table)

    branches = [
      {"test_runs",
       fn ->
         """
         SELECT 'test_runs', toString(id), toInt64(0), toUInt64(max(toUnixTimestamp64Micro(inserted_at))) FROM #{db}.test_runs
         WHERE project_id = {project_id:Int64} AND id IN {test_runs:Array(UUID)}
           AND inserted_at >= {test_runs_since:DateTime64(6)}
         GROUP BY id
         """
       end},
      {"test_case_runs",
       fn ->
         """
         SELECT 'test_case_runs', toString(test_run_id), toInt64(ifNull(shard_index, 0)) AS shard, uniqExact(id)
         FROM #{db}.test_case_runs
         WHERE project_id = {project_id:Int64} AND test_run_id IN {test_case_runs:Array(UUID)}
           AND inserted_at >= {test_case_runs_since:DateTime64(6)}
           AND inserted_at >= arrayElement({test_case_runs_report_since:Array(DateTime64(6))},
             indexOf({test_case_runs_reports:Array(String)}, concat(toString(test_run_id), '/', toString(ifNull(shard_index, 0)))))
         GROUP BY test_run_id, shard
         """
       end},
      {"command_events",
       fn ->
         """
         SELECT 'command_events', toString(id), toInt64(0), count() FROM #{db}.command_events
         WHERE project_id = {project_id:Int64} AND id IN {command_events:Array(UUID)}
         GROUP BY id
         """
       end},
      {"xcode_targets",
       fn ->
         """
         SELECT 'xcode_targets', toString(command_event_id), toInt64(toUnixTimestamp(inserted_at)), count()
         FROM #{db}.xcode_targets
         WHERE inserted_at >= {xcode_targets_since:DateTime64(6)} AND inserted_at <= {xcode_targets_until:DateTime64(6)}
           AND command_event_id IN {xcode_targets:Array(UUID)}
         GROUP BY command_event_id, inserted_at
         """
       end}
    ]

    # Every replica answers this row, so one holding none of the rows is
    # still counted, as missing them.
    replica = "SELECT 'replica' AS kind, '' AS id, toInt64(0) AS part, toUInt64(0) AS n"

    sql =
      Enum.join(
        [replica | for({table, branch} <- branches, Map.has_key?(by_table, table), do: branch.())],
        "\nUNION ALL\n"
      )

    params =
      Enum.reduce(by_table, %{"project_id" => project_id}, fn {table, inserts}, params ->
        ats = Enum.map(inserts, &DateTime.to_naive(&1.rows_inserted_at))

        Map.merge(params, %{
          table => inserts |> Enum.map(&run_id(&1.key)) |> Enum.uniq(),
          "#{table}_since" => Enum.min(ats, NaiveDateTime),
          "#{table}_until" => Enum.max(ats, NaiveDateTime)
        })
      end)

    # A shard's own report only: rows from before it was declared are an
    # earlier attempt of the shard, which a retry replaces.
    params =
      case Map.get(by_table, "test_case_runs") do
        nil ->
          params

        reports ->
          Map.merge(params, %{
            "test_case_runs_reports" => Enum.map(reports, & &1.key),
            "test_case_runs_report_since" => Enum.map(reports, &DateTime.to_naive(&1.rows_inserted_at))
          })
      end

    {sql, params}
  end

  defp run_id(key), do: key |> String.split("/") |> hd()

  defp micro(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond)
end
