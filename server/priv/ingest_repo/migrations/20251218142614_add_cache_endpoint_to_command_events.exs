defmodule Tuist.IngestRepo.Migrations.AddCacheEndpointToCommandEvents do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE command_events ADD COLUMN IF NOT EXISTS cache_endpoint String DEFAULT ''"
  end

  def down do
    execute "ALTER TABLE command_events DROP COLUMN IF EXISTS cache_endpoint"
  end
end
