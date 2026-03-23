defmodule Tuist.Repo.Migrations.AddCustomOauth2ConfigurationToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :custom_oauth2_client_id, :string
      add :custom_oauth2_encrypted_client_secret, :binary
      add :custom_oauth2_authorize_url, :string
      add :custom_oauth2_token_url, :string
      add :custom_oauth2_user_info_url, :string
    end
  end
end
