defmodule Tuist.IngestRepo.Migrations.RenameAndExtendStackTraces do
  use Ecto.Migration

  def up do
    execute("RENAME TABLE stack_traces TO test_case_run_stack_traces")

    execute(
      "ALTER TABLE test_case_run_stack_traces ADD COLUMN IF NOT EXISTS test_case_run_id Nullable(UUID)"
    )

    execute(
      "ALTER TABLE test_case_run_stack_traces RENAME COLUMN IF EXISTS attachment_id TO test_case_run_attachment_id"
    )
  end

  def down do
    execute(
      "ALTER TABLE test_case_run_stack_traces RENAME COLUMN IF EXISTS test_case_run_attachment_id TO attachment_id"
    )

    execute("ALTER TABLE test_case_run_stack_traces DROP COLUMN IF EXISTS test_case_run_id")
    execute("RENAME TABLE test_case_run_stack_traces TO stack_traces")
  end
end
