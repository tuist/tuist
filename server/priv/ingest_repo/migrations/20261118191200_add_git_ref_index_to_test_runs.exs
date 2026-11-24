defmodule Tuist.IngestRepo.Migrations.AddGitRefIndexToTestRuns do
  @moduledoc """
  Adds a token bloom filter index on the ref a test run ran on.

  The pull request comment reads a pull request's runs by
  `git_ref LIKE 'refs/pull/<number>/%'` (`Tuist.VCS`). The table is ordered
  by project and run, so without an index that read scans the project's
  whole run history. The ref's tokens (`refs`, `pull`, the number) are
  whole tokens of the pattern, which `tokenbf_v1` can match, and a pull
  request's runs sit in few granules, since run ids are time-ordered.

  `ADD INDEX` is metadata-only and covers new parts. Existing parts are
  indexed by one asynchronous `MATERIALIZE INDEX` mutation per partition
  (`IndexMaterialization.materialize_index_statements/4`), and the deploy does
  not wait for them. Parts not yet materialized are still read correctly, only
  without skipping.
  """
  use Ecto.Migration

  alias Tuist.ClickHouse.IndexMaterialization
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_runs
    ADD INDEX IF NOT EXISTS idx_git_ref git_ref
    TYPE tokenbf_v1(10240, 3, 0) GRANULARITY 1
    """

    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()", [], log: false)

    IngestRepo
    |> IndexMaterialization.partition_ids(database, "test_runs")
    |> then(
      &IndexMaterialization.materialize_index_statements(database, "test_runs", "idx_git_ref", &1)
    )
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    |> Enum.each(&execute/1)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_runs DROP INDEX IF EXISTS idx_git_ref"
  end
end
