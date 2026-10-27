defmodule Tuist.IngestRepo.Migrations.AddCacheEndpointToCacheEventTables do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE cas_events ADD COLUMN IF NOT EXISTS cache_endpoint LowCardinality(String) DEFAULT ''"

    execute "ALTER TABLE gradle_cache_events ADD COLUMN IF NOT EXISTS cache_endpoint LowCardinality(String) DEFAULT ''"

    execute "ALTER TABLE registry_download_events ADD COLUMN IF NOT EXISTS cache_endpoint LowCardinality(String) DEFAULT ''"
  end

  def down do
    execute "ALTER TABLE cas_events DROP COLUMN IF EXISTS cache_endpoint"
    execute "ALTER TABLE gradle_cache_events DROP COLUMN IF EXISTS cache_endpoint"
    execute "ALTER TABLE registry_download_events DROP COLUMN IF EXISTS cache_endpoint"
  end
end
