defmodule Tuist.IngestRepo.Migrations.AddBuildTimelineLogs do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE build_timeline_events ADD COLUMN IF NOT EXISTS log String DEFAULT ''"
    execute "ALTER TABLE build_timeline_events ADD COLUMN IF NOT EXISTS log_truncated Bool DEFAULT false"
  end

  def down do
    execute "ALTER TABLE build_timeline_events DROP COLUMN IF EXISTS log_truncated"
    execute "ALTER TABLE build_timeline_events DROP COLUMN IF EXISTS log"
  end
end
