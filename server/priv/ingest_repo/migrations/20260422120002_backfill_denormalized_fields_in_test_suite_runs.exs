defmodule Tuist.IngestRepo.Migrations.BackfillDenormalizedFieldsInTestSuiteRuns do
  @moduledoc """
  Backfills `project_id`, `is_ci`, `git_branch`, and `ran_at` on existing
  `test_suite_runs` rows by joining against `test_runs`. Mirrors the
  `test_module_runs` backfill — see that migration's moduledoc for the
  strategy.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true
  @batch_size 500_000
  @throttle_ms 1_000
  @dict_name "test_runs_denorm_dict_for_suite_runs"

  def up do
    create_dictionary()

    try do
      do_backfill(~N[1970-01-01 00:00:00.000000], 0)
    after
      drop_dictionary()
    end
  end

  def down do
    :ok
  end

  defp create_dictionary do
    IngestRepo.query!("DROP DICTIONARY IF EXISTS #{@dict_name}")

    IngestRepo.query!("""
    CREATE DICTIONARY #{@dict_name} (
      id UUID,
      project_id Int64,
      is_ci Bool,
      git_branch String,
      ran_at DateTime64(6)
    )
    PRIMARY KEY id
    SOURCE(CLICKHOUSE(TABLE 'test_runs'))
    LAYOUT(HASHED())
    LIFETIME(0)
    """)
  end

  defp drop_dictionary do
    IngestRepo.query!("DROP DICTIONARY IF EXISTS #{@dict_name}")
  end

  defp do_backfill(cursor, total_copied) do
    {:ok, %{rows: [[batch_max]]}} =
      IngestRepo.query(
        """
        SELECT maxOrNull(inserted_at) FROM (
          SELECT inserted_at FROM test_suite_runs
          WHERE project_id IS NULL AND inserted_at > {cursor:DateTime64(6)}
          ORDER BY inserted_at
          LIMIT #{@batch_size}
        )
        """,
        %{cursor: cursor}
      )

    cond do
      is_nil(batch_max) or NaiveDateTime.compare(batch_max, cursor) != :gt ->
        Logger.info("test_suite_runs backfill complete: #{total_copied} rows backfilled")
        :ok

      true ->
        Logger.info(
          "test_suite_runs backfill: cursor=#{cursor} -> #{batch_max}, #{total_copied} rows backfilled so far"
        )

        {:ok, %{num_rows: copied}} =
          IngestRepo.query(
            """
            INSERT INTO test_suite_runs (
              id, name, test_run_id, test_module_run_id, status, is_flaky,
              duration, test_case_count, avg_test_case_duration,
              shard_id, shard_index,
              project_id, is_ci, git_branch, ran_at,
              inserted_at
            )
            SELECT
              id,
              name,
              test_run_id,
              test_module_run_id,
              status,
              is_flaky,
              duration,
              test_case_count,
              avg_test_case_duration,
              shard_id,
              shard_index,
              dictGet('#{@dict_name}', 'project_id', test_run_id) AS project_id,
              dictGet('#{@dict_name}', 'is_ci', test_run_id) AS is_ci,
              dictGet('#{@dict_name}', 'git_branch', test_run_id) AS git_branch,
              dictGet('#{@dict_name}', 'ran_at', test_run_id) AS ran_at,
              inserted_at + toIntervalMicrosecond(1) AS inserted_at
            FROM test_suite_runs
            WHERE project_id IS NULL
              AND inserted_at > {cursor:DateTime64(6)}
              AND inserted_at <= {batch_max:DateTime64(6)}
              AND dictHas('#{@dict_name}', test_run_id)
            """,
            %{cursor: cursor, batch_max: batch_max},
            timeout: :infinity
          )

        Process.sleep(@throttle_ms)
        do_backfill(batch_max, total_copied + copied)
    end
  end
end
