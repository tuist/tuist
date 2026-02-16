defmodule Tuist.Repo.Migrations.AddBundleSizeAlertRuleSupport do
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      add :git_branch, :string
      add :bundle_size_metric, :integer

      modify :metric, :integer, null: true, from: {:integer, null: false}
      modify :rolling_window_size, :integer, null: true, from: {:integer, null: false}
    end
  end
end
