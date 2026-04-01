defmodule Tuist.IngestRepo.Migrations.AddTestRunIdToTestCaseRunAttachments do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE test_case_run_attachments ADD COLUMN IF NOT EXISTS test_run_id Nullable(UUID)")
  end

  def down do
    execute("ALTER TABLE test_case_run_attachments DROP COLUMN IF EXISTS test_run_id")
  end
end
