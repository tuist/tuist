defmodule Tuist.IngestRepo.Migrations.CreatePartitionedTestCaseRunCopies do
  @moduledoc """
  Creates partitioned, expiring successors of the five `test_case_runs` copies,
  each fed by its own materialized view from the moment it exists.

  The current copies are unpartitioned and never expire, so together they grow
  with every run ever reported. Each successor is partitioned by when its rows
  were inserted and drops whole parts once they pass its retention:

    * `test_case_runs_by_test_run_v2`, `test_case_runs_by_project_v2` and
      `test_case_runs_by_shard_id_v2` keep 90 days. They back run, shard and
      project listings and billing, and are hydrated from `test_case_runs`,
      which keeps its own, longer history for test case analytics.
    * `test_case_runs_by_inserted_at_v2` and `test_case_runs_by_commit_v2` keep
      30 days. The first only serves hourly charts and alert scans, the second
      the same-commit lookup at ingestion.

  The shapes change where the rebuild allows it: `by_test_run` sorts by name
  within a run, `by_inserted_at` keeps only the columns its readers select, and
  `by_shard_id` and `by_inserted_at` become ReplacingMergeTree so re-inserted
  rows and backfill overlap collapse. `by_shard_id` also stops taking unsharded
  runs: its predecessor filtered on the `assumeNotNull` alias rather than the
  column, so it holds every run, the unsharded ones under the nil UUID.
  `by_commit` excludes network-trusted reports, like its predecessor's view
  since `ExcludeNetworkReportsFromTestValidation`.

  Only the tables and views are created here. Rows from before the views
  existed are copied by `Tuist.Release.backfill_test_case_run_copies/0`, and
  reads move to these tables once that has run.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @status "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"

  def up do
    create_copy(
      "test_case_runs_by_inserted_at_v2",
      """
      id UUID,
      project_id Int64,
      inserted_at DateTime64(6),
      test_case_id Nullable(UUID),
      status #{@status},
      duration Int32,
      scheme String,
      is_ci Bool,
      is_flaky Bool
      """,
      engine: Migration.engine("ReplacingMergeTree"),
      partition_by: "toYYYYMMDD(inserted_at)",
      order_by: "project_id, inserted_at, id",
      retention_days: 30,
      select:
        "id, project_id, inserted_at, test_case_id, status, duration, scheme, is_ci, is_flaky"
    )

    create_copy(
      "test_case_runs_by_commit_v2",
      """
      project_id Int64,
      git_commit_sha String,
      scheme String,
      is_ci Bool,
      status #{@status},
      id UUID,
      test_case_id Nullable(UUID),
      is_flaky Bool,
      inserted_at DateTime64(6)
      """,
      engine: Migration.engine("ReplacingMergeTree(inserted_at)"),
      partition_by: "toMonday(inserted_at)",
      order_by: "project_id, git_commit_sha, scheme, is_ci, status, id",
      retention_days: 30,
      select:
        "project_id, git_commit_sha, scheme, is_ci, status, id, test_case_id, is_flaky, inserted_at",
      where: "submission_auth != 'network_trusted'"
    )

    create_copy(
      "test_case_runs_by_test_run_v2",
      """
      id UUID,
      test_run_id UUID,
      status #{@status},
      is_flaky Bool,
      is_new Bool,
      duration Int32,
      inserted_at DateTime64(6),
      ran_at DateTime64(6),
      name String,
      project_id Int64,
      test_case_id Nullable(UUID)
      """,
      engine: Migration.engine("ReplacingMergeTree(inserted_at)"),
      partition_by: "toYYYYMM(inserted_at)",
      order_by: "test_run_id, name, id",
      retention_days: 90,
      select:
        "id, test_run_id, status, is_flaky, is_new, duration, inserted_at, ran_at, name, project_id, test_case_id"
    )

    create_copy(
      "test_case_runs_by_shard_id_v2",
      """
      id UUID,
      shard_id UUID,
      name String,
      status #{@status},
      is_flaky Bool,
      is_new Bool,
      duration Int32,
      shard_index Nullable(Int32),
      project_id Int64,
      test_case_id Nullable(UUID),
      ran_at DateTime64(6),
      inserted_at DateTime64(6)
      """,
      engine: Migration.engine("ReplacingMergeTree(inserted_at)"),
      partition_by: "toYYYYMM(inserted_at)",
      order_by: "shard_id, name, id",
      retention_days: 90,
      select:
        "id, assumeNotNull(shard_id) AS shard_id, name, status, is_flaky, is_new, duration, shard_index, " <>
          "project_id, test_case_id, ran_at, inserted_at",
      # Qualified: unqualified, `shard_id` is the `assumeNotNull` alias and never NULL.
      where: "test_case_runs.shard_id IS NOT NULL"
    )

    create_copy(
      "test_case_runs_by_project_v2",
      """
      id UUID,
      project_id Int64,
      ran_at DateTime64(6),
      inserted_at DateTime64(6),
      name String,
      status #{@status},
      is_flaky Bool,
      is_new Bool,
      is_ci Bool,
      is_quarantined Bool,
      duration Int32,
      test_case_id Nullable(UUID),
      account_id Nullable(Int64),
      scheme String,
      git_branch String
      """,
      engine: Migration.engine("ReplacingMergeTree(inserted_at)"),
      partition_by: "toYYYYMM(inserted_at)",
      order_by: "project_id, ran_at, id",
      retention_days: 90,
      select:
        "id, project_id, ran_at, inserted_at, name, status, is_flaky, is_new, is_ci, is_quarantined, duration, " <>
          "test_case_id, account_id, scheme, git_branch"
    )
  end

  def down do
    for table <- ~w(
          test_case_runs_by_inserted_at_v2
          test_case_runs_by_commit_v2
          test_case_runs_by_test_run_v2
          test_case_runs_by_shard_id_v2
          test_case_runs_by_project_v2
        ) do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute "DROP VIEW IF EXISTS #{table}_mv"
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute "DROP TABLE IF EXISTS #{table}"
    end
  end

  defp create_copy(table, columns, opts) do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE TABLE IF NOT EXISTS #{table} (
    #{columns}
    ) ENGINE = #{Keyword.fetch!(opts, :engine)}
    PARTITION BY #{Keyword.fetch!(opts, :partition_by)}
    ORDER BY (#{Keyword.fetch!(opts, :order_by)})
    TTL toDateTime(inserted_at) + INTERVAL #{Keyword.fetch!(opts, :retention_days)} DAY
    SETTINGS ttl_only_drop_parts = 1
    """

    where_clause =
      case Keyword.get(opts, :where) do
        nil -> ""
        condition -> "\nWHERE #{condition}"
      end

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS #{table}_mv TO #{table} AS
    SELECT #{Keyword.fetch!(opts, :select)}
    FROM test_case_runs#{where_clause}
    """
  end
end
