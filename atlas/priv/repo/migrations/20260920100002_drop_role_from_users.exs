defmodule Atlas.Repo.Migrations.DropRoleFromUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      remove :role
    end
  end

  def down do
    alter table(:users) do
      add :role, :string, null: false, default: "employee"
    end
  end
end
