defmodule Tuist.Repo.Migrations.ReplaceCiOnlyWithEnvironmentOnAlertRules do
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      remove :ci_only
      add :environment, :string, null: false, default: "any"
    end
  end
end
