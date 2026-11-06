defmodule Tuist.Repo.Migrations.AddCredentialsRevokedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Credentials that act for the user and were authenticated at or before
      # this moment are rejected. Set by password resets.
      add :credentials_revoked_at, :timestamptz
    end
  end
end
