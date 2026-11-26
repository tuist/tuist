defmodule Tuist.ClickHouse.Inserts do
  @moduledoc """
  ClickHouse inserts a later write waits for (`Tuist.ClickHouse.Insert`).

  An acknowledged insert has reached one replica; the others fetch its part
  on their own time, table by table. A write that tells readers some rows are
  complete, such as a run's coverage totals, therefore goes in only once
  every replica holds those rows. The writer records each insert here, in
  PostgreSQL, under the unit of rows it wrote (`key`), and whoever makes the
  later write counts the rows on every replica (`on_every_replica/1`) before
  making it, then marks the inserts synced. A newer insert of the same unit
  replaces the record.
  """
  import Ecto.Query

  alias Tuist.ClickHouse.Insert
  alias Tuist.IngestRepo
  alias Tuist.Repo

  @retention_hours 24
  @replaced_fields [:project_id, :rows_inserted_at, :row_count, :git_commit_sha, :test_run_id, :synced_at, :inserted_at]

  @doc """
  Records that `key`'s rows, sharing `rows_inserted_at`, were inserted into
  `table`. `rows:` is how many there are, for rows that don't share one
  `inserted_at` but were all inserted at or after it. `sha:` names the
  commit whose fold reads them (`Tuist.Tests.Coverage.RunInputs`), which
  takes a commit's insert recorded without `rows:` as one still being written.
  `test_run_id:` names the run an insert recorded without `sha:` waits for.
  """
  def record(table, key, project_id, rows_inserted_at, opts \\ []) do
    Repo.insert_all(
      Insert,
      [
        %{
          clickhouse_table: table,
          key: key,
          project_id: project_id,
          rows_inserted_at: utc(rows_inserted_at),
          row_count: Keyword.get(opts, :rows),
          git_commit_sha: Keyword.get(opts, :sha),
          test_run_id: Keyword.get(opts, :test_run_id),
          synced_at: nil,
          inserted_at: DateTime.utc_now()
        }
      ],
      on_conflict: {:replace, @replaced_fields},
      conflict_target: [:clickhouse_table, :key]
    )

    :ok
  end

  @doc "The recorded inserts of `key`, by table."
  def by_table(key) do
    from(i in Insert, where: i.key == ^key) |> Repo.all() |> Map.new(&{&1.clickhouse_table, &1})
  end

  @doc "Marks the inserts synced: every replica holds their rows."
  def mark_synced(inserts) do
    for %Insert{} = insert <- inserts do
      Repo.update_all(
        from(i in Insert,
          where:
            i.clickhouse_table == ^insert.clickhouse_table and i.key == ^insert.key and
              i.rows_inserted_at == ^insert.rows_inserted_at
        ),
        set: [synced_at: DateTime.utc_now()]
      )
    end

    :ok
  end

  @doc "Drops the records no write waits for any more."
  def prune do
    {count, _} = Repo.delete_all(from(i in Insert, where: i.inserted_at < ago(@retention_hours, "hour")))
    count
  end

  @doc """
  Runs `sql`, a query that reads tables qualified with `database/0`, on every
  replica of the `default` cluster, adding the replica's number as the first
  column. A replica that can't be reached fails the query, since it can't be
  told apart from one that lacks the rows. Without the cluster, as on a single
  server, it runs on that server as replica 0.
  """
  def on_every_replica(sql) do
    if replicas() > 0,
      do: "SELECT _shard_num, * FROM clusterAllReplicas('default', view(#{sql}))",
      else: "SELECT toUInt32(0), * FROM (#{sql})"
  end

  @doc """
  How many replicas the `default` cluster has, as the managed deployment's
  names every one: 0 without the cluster.
  """
  def replicas do
    case :persistent_term.get({__MODULE__, :replicas}, nil) do
      nil ->
        %{rows: [[count]]} = IngestRepo.query!("SELECT count() FROM system.clusters WHERE cluster = 'default'")
        :persistent_term.put({__MODULE__, :replicas}, count)
        count

      count ->
        count
    end
  end

  @doc """
  The ingest database, quoted, to qualify tables with in `on_every_replica/1`:
  a replica answering for another doesn't inherit the session's database.
  """
  def database do
    "`" <> (IngestRepo.config() |> Keyword.fetch!(:database) |> to_string() |> String.replace("`", "")) <> "`"
  end

  # At microsecond precision whatever the rows' own, such as whole seconds.
  defp utc(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> utc()
  defp utc(%DateTime{microsecond: {value, _precision}} = at), do: %{at | microsecond: {value, 6}}
end
