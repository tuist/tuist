defmodule Tuist.Repo.Migrations.AddCacheKeyToOnceActions do
  use Ecto.Migration

  def change do
    alter table(:once_actions) do
      add :cache_key, :string, size: 128, default: "", null: false
    end

    create index(:once_actions, [:once_run_id, :cache_key])
  end
end
