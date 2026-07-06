defmodule Tuist.Repo.Migrations.AddKuraCacheWritePolicyToAccounts do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:accounts) do
      add :kura_cache_write_policy, :integer, default: 0, null: false
    end
  end
end
