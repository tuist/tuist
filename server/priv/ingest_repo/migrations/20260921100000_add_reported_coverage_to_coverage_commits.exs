defmodule Tuist.IngestRepo.Migrations.AddReportedCoverageToCoverageCommits do
  @moduledoc """
  A commit's reported coverage beside the observed one: what its runs
  measured plus the coverage carried forward for the tests they skipped, with
  how many tests were skipped, how many were carried, and what is left as a
  gap (`Tuist.Tests.Coverage.Reported`).
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @columns [
    {"reported_covered_lines", "UInt64 DEFAULT 0"},
    {"reported_executable_lines", "UInt64 DEFAULT 0"},
    {"reported_kind", "LowCardinality(String) DEFAULT ''"},
    {"skipped_tests_count", "UInt32 DEFAULT 0"},
    {"carried_tests_count", "UInt32 DEFAULT 0"},
    {"gap_files_count", "UInt32 DEFAULT 0"},
    {"carried_from", "Array(String) DEFAULT []"}
  ]

  def up do
    for {name, type} <- @columns do
      execute("ALTER TABLE coverage_commits ADD COLUMN IF NOT EXISTS #{name} #{type}")
    end
  end

  def down do
    for {name, _type} <- Enum.reverse(@columns) do
      execute("ALTER TABLE coverage_commits DROP COLUMN IF EXISTS #{name}")
    end
  end
end
