defmodule Tuist.Repo.Migrations.CreateRunnerActionsCacheEntries do
  use Ecto.Migration

  def change do
    create table(:runner_actions_cache_entries, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :repository_id, :bigint, null: false
      add :scope, :string, null: false
      add :key, :text, null: false
      add :version, :string, null: false
      add :size_bytes, :bigint
      add :node_name, :string, null: false
      add :committed_at, :timestamptz
      add :stored_at, :timestamptz
      add :last_used_at, :timestamptz, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(
             :runner_actions_cache_entries,
             [:account_id, :repository_id, :scope, :version, :key],
             name: :runner_actions_cache_entries_unique_index
           )

    # Prefix matches of keys and restore keys.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(
             :runner_actions_cache_entries,
             [:repository_id, :scope, "key text_pattern_ops"],
             name: :runner_actions_cache_entries_key_prefix_index
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_actions_cache_entries, [:last_used_at])
  end
end
