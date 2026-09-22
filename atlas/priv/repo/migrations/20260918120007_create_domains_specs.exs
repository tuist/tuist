defmodule Atlas.Repo.Migrations.CreateDomainsSpecs do
  use Ecto.Migration

  def change do
    create table(:domains_specs, primary_key: false) do
      add :domain_id, references(:domains, type: :binary_id, on_delete: :delete_all), null: false
      add :spec_id, references(:specs, type: :binary_id, on_delete: :delete_all), null: false
    end

    create unique_index(:domains_specs, [:domain_id, :spec_id])
    create index(:domains_specs, [:spec_id])
  end
end
