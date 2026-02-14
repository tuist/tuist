defmodule Tuist.IngestRepo.Migrations.RenameFormattedFramesToTriggeredThreadFrames do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE stack_traces ADD COLUMN IF NOT EXISTS triggered_thread_frames String DEFAULT ''"
    )

    execute("ALTER TABLE stack_traces UPDATE triggered_thread_frames = formatted_frames WHERE 1=1")
  end

  def down do
    execute("ALTER TABLE stack_traces DROP COLUMN IF EXISTS triggered_thread_frames")
  end
end
