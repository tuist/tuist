defmodule Tuist.Repo.Migrations.AddEnvironmentToAlertRules do
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      add :environment, :string, null: false, default: "any"
    end
  end
end
