defmodule Tuist.Repo.Migrations.AddCacheWritePolicyToAccounts do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:accounts) do
      add :cache_write_policy, :integer, default: 0, null: false
    end
  end
end
