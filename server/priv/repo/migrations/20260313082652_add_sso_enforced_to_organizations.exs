defmodule Tuist.Repo.Migrations.AddSsoEnforcedToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :sso_enforced, :boolean, default: false, null: false
    end
  end
end
