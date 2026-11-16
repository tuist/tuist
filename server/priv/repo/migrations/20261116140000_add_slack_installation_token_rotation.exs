defmodule Tuist.Repo.Migrations.AddSlackInstallationTokenRotation do
  use Ecto.Migration

  def change do
    alter table(:slack_installations) do
      # Null for long-lived tokens issued before Slack token rotation was
      # enabled; set once the token has been exchanged with oauth.v2.exchange.
      add :refresh_token, :binary
      add :access_token_expires_at, :timestamptz
    end
  end
end
