defmodule Cache.KeyValueRepo.Migrations.CreatePendingReplicationEntries do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:pending_replication_entries, primary_key: false) do
      add(:key, :text, primary_key: true)
      add(:json_payload, :text, null: false)
      add(:source_node, :text)
      add(:source_updated_at, :utc_datetime_usec)
      add(:last_accessed_at, :utc_datetime_usec, null: false)
      add(:replication_enqueued_at, :utc_datetime_usec, null: false)
    end

    create(index(:pending_replication_entries, [:replication_enqueued_at, :key]))
  end
end
