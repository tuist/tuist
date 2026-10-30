defmodule Atlas.Repo.Migrations.AddCodingRepositoryPreferences do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :coding_preferences, :map, null: false, default: %{}
    end

    alter table(:orbit_threads) do
      add :repository, :string, size: 140
    end
  end
end
