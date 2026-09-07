defmodule Tuist.IngestRepo.Migrations.AddBuildStepLogs do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE build_steps ADD COLUMN IF NOT EXISTS log String DEFAULT ''"
    execute "ALTER TABLE build_steps ADD COLUMN IF NOT EXISTS log_truncated Bool DEFAULT false"
  end

  def down do
    execute "ALTER TABLE build_steps DROP COLUMN IF EXISTS log_truncated"
    execute "ALTER TABLE build_steps DROP COLUMN IF EXISTS log"
  end
end
