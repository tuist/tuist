defmodule Cache.KeyValueRepo.Migrations.CreateKeyValueEntries do
  use Ecto.Migration

  def change do
    create table(:key_value_entries) do
      add :key, :text, null: false
      add :json_payload, :text, null: false
      add :last_accessed_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:key_value_entries, [:key])
    create index(:key_value_entries, [:last_accessed_at, :id])
  end
end
