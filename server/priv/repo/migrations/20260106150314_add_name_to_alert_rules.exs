defmodule Tuist.Repo.Migrations.AddNameToAlertRules do
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      add :name, :string, null: false, default: "Untitled"
    end
  end
end
