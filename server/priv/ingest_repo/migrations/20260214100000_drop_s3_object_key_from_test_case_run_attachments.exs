defmodule Tuist.IngestRepo.Migrations.DropS3ObjectKeyFromTestCaseRunAttachments do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE test_case_run_attachments DROP COLUMN IF EXISTS s3_object_key")
  end

  def down do
    execute(
      "ALTER TABLE test_case_run_attachments ADD COLUMN IF NOT EXISTS s3_object_key String DEFAULT ''"
    )
  end
end
