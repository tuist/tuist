defmodule Tuist.IngestRepo.Migrations.AddCasOperationToReapiCacheEvents do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE reapi_cache_events MODIFY COLUMN operation Enum8('action_cache' = 0, 'cas' = 1) SETTINGS mutations_sync = 1"
    )
  end

  def down do
    execute(
      "ALTER TABLE reapi_cache_events MODIFY COLUMN operation Enum8('action_cache' = 0) SETTINGS mutations_sync = 1"
    )
  end
end
