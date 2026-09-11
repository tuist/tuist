defmodule Tuist.Repo.Migrations.AddSsoDefaultRoleToOrganizations do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      # Postgres fills existing rows from the default without rewriting the
      # table, so organizations keep enrolling SSO members as `user`.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :sso_default_role, :string, default: "user"
    end
  end

  def down do
    alter table(:organizations) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sso_default_role
    end
  end
end
