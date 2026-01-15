defmodule Tuist.Repo.Migrations.ChangeOauthTokensStateToText do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def up do
    alter table(:oauth_tokens) do
      modify :state, :text
    end
  end

  def down do
    alter table(:oauth_tokens) do
      modify :state, :string, size: 10_000
    end
  end
end
