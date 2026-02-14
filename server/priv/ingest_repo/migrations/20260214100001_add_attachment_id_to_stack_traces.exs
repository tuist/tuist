defmodule Tuist.IngestRepo.Migrations.AddAttachmentIdToStackTraces do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE stack_traces ADD COLUMN IF NOT EXISTS attachment_id Nullable(UUID)")
  end

  def down do
    execute("ALTER TABLE stack_traces DROP COLUMN IF EXISTS attachment_id")
  end
end
