defmodule LuftServer.Repo.Migrations.CreateOrganizationOpsRepositories do
  use Ecto.Migration

  def change do
    create table(:organization_ops_repositories, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :organization_id, :bigint, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:organization_ops_repositories, [:organization_id])
  end
end
