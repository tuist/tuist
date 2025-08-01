defmodule Tuist.Repo.Migrations.DropOktaSiteFromOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      remove :okta_site, :string
    end
  end
end
