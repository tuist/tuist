defmodule Tuist.Repo.Migrations.AddProvisionedByOrganizationIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # excellent_migrations:safety-assured-for-next-line column_reference_added
      add :provisioned_by_organization_id, references(:organizations, on_delete: :nilify_all)
    end
  end
end
