defmodule Cache.KeyValueRepo.Migrations.AddDistributedKvFields do
  use Ecto.Migration

  def change do
    alter table(:key_value_entries) do
      add :source_updated_at, :utc_datetime_usec
      add :replication_enqueued_at, :utc_datetime_usec
    end

    create index(:key_value_entries, [:replication_enqueued_at], where: "replication_enqueued_at IS NOT NULL")

    create table(:distributed_kv_state, primary_key: false) do
      add :name, :text, primary_key: true
      add :updated_at_value, :utc_datetime_usec
      add :key_value, :text
    end
  end
end
