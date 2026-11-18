defmodule Tuist.Repo.Migrations.AddAccountsCredentialsRevokedAt do
  @moduledoc """
  `accounts.credentials_revoked_at` rejects account JWTs (OIDC exchanges,
  agent and OAuth tokens) issued at or before it, which are not stored and
  could otherwise not be revoked. See `Tuist.Accounts.CredentialRevocation`.
  """
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :credentials_revoked_at, :timestamptz
    end
  end
end
