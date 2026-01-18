defmodule Tuist.Repo.Migrations.AddTokenUsagesAccountTimestampIndex do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    create index(:token_usages, [:account_id, :timestamp])
  end
end
