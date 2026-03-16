defmodule Cache.DistributedKV.Repo.Migrations.CreateKeyValueEntries do
  use Ecto.Migration

  def change do
    create table(:key_value_entries, primary_key: false) do
      add :key, :text, primary_key: true
      add :account_handle, :text, null: false
      add :project_handle, :text, null: false
      add :cas_id, :text, null: false
      add :json_payload, :text, null: false
      add :source_node, :text, null: false
      add :source_updated_at, :timestamptz, null: false
      add :last_accessed_at, :timestamptz, null: false
      add :updated_at, :timestamptz, null: false
      add :deleted_at, :timestamptz
    end

    create index(:key_value_entries, [:updated_at, :key])
    create index(:key_value_entries, [:last_accessed_at, :key])
    create index(:key_value_entries, [:account_handle, :project_handle])
    create index(:key_value_entries, [:deleted_at], where: "deleted_at IS NOT NULL")
  end
end
