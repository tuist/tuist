defmodule Tuist.Repo.Migrations.AddLastGoogleAuthenticatedAtToUsers do
  use Ecto.Migration

  # Operator grants are honoured over MCP against a bearer access token, which
  # carries no record of how its owner authenticated. Recording when a user last
  # proved Google Workspace SSO gives that check something to stand on, so a
  # grant cannot be combined with a password-authenticated operator credential.
  def change do
    alter table(:users) do
      add :last_google_authenticated_at, :naive_datetime
    end
  end
end
