defmodule Tuist.Repo.Migrations.AddCustomOauth2ConfigurationToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :oauth2_client_id, :string
      add :oauth2_encrypted_client_secret, :binary
      add :oauth2_authorize_url, :string
      add :oauth2_token_url, :string
      add :oauth2_user_info_url, :string
    end
  end
end
