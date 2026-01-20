defmodule Tuist.Repo.Migrations.AddUniqueNameIndexToAccountTokens do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    create unique_index(:account_tokens, [:account_id, :name])
  end
end
