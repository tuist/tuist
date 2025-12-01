defmodule Cache.Repo.Migrations.CreateKeyValueEntries do
  use Ecto.Migration

  def change do
    create table(:key_value_entries) do
      add :key, :text, null: false
      add :json_payload, :text, null: false

      timestamps()
    end

    create unique_index(:key_value_entries, [:key])
  end
end
