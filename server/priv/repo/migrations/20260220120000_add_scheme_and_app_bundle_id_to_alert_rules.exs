defmodule Tuist.Repo.Migrations.AddSchemeAndAppBundleIdToAlertRules do
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      add :scheme, :string, null: false, default: ""
      add :app_bundle_id, :string, null: false, default: ""
    end
  end
end
