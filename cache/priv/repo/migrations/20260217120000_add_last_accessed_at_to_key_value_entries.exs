defmodule Cache.Repo.Migrations.AddLastAccessedAtToKeyValueEntries do
  use Ecto.Migration

  def change do
    alter table(:key_value_entries) do
      add :last_accessed_at, :utc_datetime_usec
    end

    create index(:key_value_entries, [:last_accessed_at])
  end
end
