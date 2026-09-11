defmodule Tuist.Repo.Migrations.AddRoleToInvitations do
  use Ecto.Migration

  def up do
    alter table(:invitations) do
      # Postgres fills existing rows from the default without rewriting the
      # table, so pending invitations keep resolving to the historical role.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :role, :string, default: "user"
    end
  end

  def down do
    alter table(:invitations) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :role
    end
  end
end
