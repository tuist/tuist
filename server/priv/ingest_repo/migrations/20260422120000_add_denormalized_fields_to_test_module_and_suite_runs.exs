defmodule Tuist.IngestRepo.Migrations.AddDenormalizedFieldsToTestModuleAndSuiteRuns do
  @moduledoc """
  Adds `project_id`, `is_ci`, `git_branch`, and `ran_at` to `test_module_runs`
  and `test_suite_runs` so queries that currently join through `test_runs` to
  filter by project/branch/ran_at can filter directly, without a subquery.

  Columns are nullable for existing rows; a later migration backfills them
  from `test_runs` and a follow-up migration marks them non-nullable once
  backfill is verified. Same pattern used for `test_case_runs` in
  20251127103046_add_denormalized_fields_to_test_case_runs.exs.

  Raw `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` instead of the Ecto DSL so
  the migration is idempotent on re-run. See 20260410120000 for context.
  """
  use Ecto.Migration

  def up do
    for {table, column, type, default} <- [
          {"test_module_runs", "project_id", "Nullable(Int64)", nil},
          {"test_module_runs", "is_ci", "Bool", "false"},
          {"test_module_runs", "git_branch", "String", "''"},
          {"test_module_runs", "ran_at", "Nullable(DateTime64(6))", nil},
          {"test_suite_runs", "project_id", "Nullable(Int64)", nil},
          {"test_suite_runs", "is_ci", "Bool", "false"},
          {"test_suite_runs", "git_branch", "String", "''"},
          {"test_suite_runs", "ran_at", "Nullable(DateTime64(6))", nil}
        ] do
      default_clause = if default, do: " DEFAULT #{default}", else: ""

      execute("ALTER TABLE #{table} ADD COLUMN IF NOT EXISTS #{column} #{type}#{default_clause}")
    end
  end

  def down do
    for {table, column} <- [
          {"test_module_runs", "project_id"},
          {"test_module_runs", "is_ci"},
          {"test_module_runs", "git_branch"},
          {"test_module_runs", "ran_at"},
          {"test_suite_runs", "project_id"},
          {"test_suite_runs", "is_ci"},
          {"test_suite_runs", "git_branch"},
          {"test_suite_runs", "ran_at"}
        ] do
      execute("ALTER TABLE #{table} DROP COLUMN IF EXISTS #{column}")
    end
  end
end
