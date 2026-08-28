defmodule Tuist.IngestRepo.Migrations.AddObservedAtToReapiCacheEvents do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE reapi_cache_events ADD COLUMN observed_at DateTime64(3, 'UTC') DEFAULT toDateTime64(inserted_at, 3, 'UTC')"
    )
  end

  def down do
    execute("ALTER TABLE reapi_cache_events DROP COLUMN observed_at")
  end
end
