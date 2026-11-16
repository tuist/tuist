defmodule Tuist.Repo.Migrations.AddOauth2ClientAuthenticationMethodToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      # 0 = client_secret_basic (the stored client secret), 1 = private_key_jwt.
      add :oauth2_client_authentication_method, :integer, null: false, default: 0
    end
  end
end
