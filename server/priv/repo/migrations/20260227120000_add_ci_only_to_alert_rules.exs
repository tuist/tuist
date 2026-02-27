defmodule Tuist.Repo.Migrations.AddCiOnlyToAlertRules do
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      add :ci_only, :boolean, null: false, default: false
    end
  end
end
