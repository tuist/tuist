defmodule Tuist.Repo.Migrations.AddBundleSizeAlertRuleSupport do
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      add :git_branch, :string

      modify :metric, :integer, null: true, from: {:integer, null: false}
      modify :rolling_window_size, :integer, null: true, from: {:integer, null: false}
    end
  end
end
