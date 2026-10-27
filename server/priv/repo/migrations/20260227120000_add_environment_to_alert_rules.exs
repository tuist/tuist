defmodule Tuist.Repo.Migrations.AddEnvironmentToAlertRules do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:alert_rules) do
      add :environment, :integer, null: false, default: 0
    end
  end
end
