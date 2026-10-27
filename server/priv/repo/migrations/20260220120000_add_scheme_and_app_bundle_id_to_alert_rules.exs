defmodule Tuist.Repo.Migrations.AddSchemeAndBundleNameToAlertRules do
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      add :scheme, :string, null: false, default: ""
      add :bundle_name, :string, null: false, default: ""
    end
  end
end
