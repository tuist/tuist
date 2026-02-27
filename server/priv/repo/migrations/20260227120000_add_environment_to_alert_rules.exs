defmodule Tuist.Repo.Migrations.AddEnvironmentToAlertRules do
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      add :environment, :integer, null: false, default: 0
    end
  end
end
