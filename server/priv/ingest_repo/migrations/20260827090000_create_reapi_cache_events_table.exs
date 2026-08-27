defmodule Tuist.IngestRepo.Migrations.CreateReapiCacheEventsTable do
  use Ecto.Migration

  def change do
    create table(:reapi_cache_events,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, operation, inserted_at) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :client_kind, :"LowCardinality(String)", null: false
      add :operation, :"Enum8('action_cache' = 0)", null: false
      add :outcome, :"Enum8('hit' = 0, 'miss' = 1, 'write' = 2)", null: false
      add :action_digest, :string, null: false
      add :size, :UInt64, null: false
      add :duration_ms, :UInt64, null: false
      add :invocation_id, :string, null: false
      add :action_mnemonic, :string, null: false
      add :target_label, :string, null: false
      add :configuration_id, :string, null: false
      add :project_id, :Int64, null: false
      add :account_handle, :string, null: false
      add :project_handle, :string, null: false
      add :cache_endpoint, :"LowCardinality(String)", null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
