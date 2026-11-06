defmodule Atlas.Repo.Migrations.AddOrbitThreadDomain do
  use Ecto.Migration

  def change do
    alter table(:orbit_threads) do
      add :domain, :string
    end

    create index(:orbit_threads, [:domain, :status])
  end
end
