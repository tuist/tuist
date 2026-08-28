defmodule Tuist.IngestRepo.Migrations.ChangeReapiCacheEventSizeToUInt64 do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE reapi_cache_events MODIFY COLUMN size UInt64 SETTINGS mutations_sync = 1"
    )
  end

  def down do
    execute("ALTER TABLE reapi_cache_events MODIFY COLUMN size Int64 SETTINGS mutations_sync = 1")
  end
end
