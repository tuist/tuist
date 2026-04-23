defmodule Tuist.IngestRepo.Migrations.BackfillDenormalizedFieldsInTestModuleRuns do
  @moduledoc """
  Backfills `project_id`, `is_ci`, `git_branch`, and `ran_at` on existing
  `test_module_runs` rows by joining against `test_runs`. New rows ingested
  after the schema migration already populate these columns; only legacy
  rows (`project_id IS NULL`) are touched.

  ## Strategy

  Mirrors the pattern in
  `20251118211224_backfill_test_runs_from_command_events.exs`:

  1. Create a `HASHED` dictionary over `test_runs` so per-row lookups are
     O(1) in memory instead of running a JOIN across all parts.
  2. Issue a single `ALTER TABLE ... UPDATE` mutation with
     `mutations_sync = 1`, which rewrites each affected part in place.
     This is friendlier to Keeper than hundreds of batched `INSERT`s:
     one mutation entry instead of many block entries, no duplicate rows
     for `ReplacingMergeTree` to dedupe, and no risk of hitting
     `parts_to_throw_insert` while merges catch up.
  3. Drop the dictionary once the mutation completes.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true
  @dict_name "test_runs_denorm_dict_for_module_runs"

  def up do
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

    Logger.info("Starting test_module_runs denormalized backfill mutation")

    IngestRepo.query!(
      """
      ALTER TABLE test_module_runs
      UPDATE
        project_id = dictGet('#{@dict_name}', 'project_id', test_run_id),
        is_ci = dictGet('#{@dict_name}', 'is_ci', test_run_id),
        git_branch = dictGet('#{@dict_name}', 'git_branch', test_run_id),
        ran_at = dictGet('#{@dict_name}', 'ran_at', test_run_id)
      WHERE project_id IS NULL
        AND dictHas('#{@dict_name}', test_run_id)
      SETTINGS mutations_sync = 1
      """,
      [],
      timeout: :infinity
    )

    Logger.info("Finished test_module_runs denormalized backfill mutation")

    IngestRepo.query!("DROP DICTIONARY #{@dict_name}")
  end

  def down do
    :ok
  end
end
