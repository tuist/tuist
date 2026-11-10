defmodule Tuist.Repo.Migrations.AddSsoAdditionalOrganizationIdsToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      # PostgreSQL 16 stores constant defaults without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :sso_additional_organization_ids, {:array, :string}, null: false, default: []
    end
  end
end
