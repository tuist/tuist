defmodule Atlas.Repo.Migrations.AddOrbitModelSelection do
  use Ecto.Migration

  def change do
    alter table(:orbit_threads) do
      add :model, :text
    end

    alter table(:orbit_runs) do
      add :model, :text
    end
  end
end
