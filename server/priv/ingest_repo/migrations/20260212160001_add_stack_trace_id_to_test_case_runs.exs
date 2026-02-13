defmodule Tuist.IngestRepo.Migrations.AddStackTraceIdToTestCaseRuns do
  use Ecto.Migration

  def up do
    alter table(:test_case_runs) do
      add :stack_trace_id, :"Nullable(UUID)"
    end

    execute(
      "ALTER TABLE test_case_runs ADD INDEX idx_stack_trace_id (stack_trace_id) TYPE bloom_filter GRANULARITY 4"
    )
  end

  def down do
    execute("ALTER TABLE test_case_runs DROP INDEX IF EXISTS idx_stack_trace_id")

    alter table(:test_case_runs) do
      remove :stack_trace_id
    end
  end
end
