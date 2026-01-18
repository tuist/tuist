defmodule Tuist.Repo.Migrations.DropOktaSiteFromOrganizations do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:organizations) do
      remove :okta_site, :string
    end
  end
end
