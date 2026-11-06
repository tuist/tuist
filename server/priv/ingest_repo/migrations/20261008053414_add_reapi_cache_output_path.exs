defmodule Tuist.IngestRepo.Migrations.AddReapiCacheOutputPath do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE reapi_cache_events ADD COLUMN IF NOT EXISTS output_path String DEFAULT ''"
    )
  end

  def down do
    execute("ALTER TABLE reapi_cache_events DROP COLUMN IF EXISTS output_path")
  end
end
