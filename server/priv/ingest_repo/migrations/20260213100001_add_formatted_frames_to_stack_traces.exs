defmodule Tuist.IngestRepo.Migrations.AddFormattedFramesToStackTraces do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE stack_traces ADD COLUMN IF NOT EXISTS formatted_frames String DEFAULT ''"
    )
  end

  def down do
    execute("ALTER TABLE stack_traces DROP COLUMN IF EXISTS formatted_frames")
  end
end
