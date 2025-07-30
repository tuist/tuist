defmodule Tuist.Repo.Migrations.AddOktaConfigurationToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :okta_client_id, :string
      add :okta_client_secret, :string
      add :okta_site, :string
    end
  end
end
