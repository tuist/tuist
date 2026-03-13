defmodule Tuist.Repo.Migrations.AddSsoEnforcedToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :sso_enforced, :boolean, default: false, null: false
    end
  end
end
