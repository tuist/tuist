defmodule Cache.Repo.Migrations.AddLastAccessedAtIdIndexToKeyValueEntries do
  use Ecto.Migration

  def change do
    create index(:key_value_entries, [:last_accessed_at, :id])
  end
end
