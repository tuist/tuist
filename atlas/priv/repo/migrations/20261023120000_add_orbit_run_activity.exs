defmodule Atlas.Repo.Migrations.AddOrbitRunActivity do
  use Ecto.Migration

  def change do
    alter table(:orbit_runs) do
      add :activity, :string
    end
  end
end
