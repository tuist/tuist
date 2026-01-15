defmodule Tuist.Repo.Migrations.AddAlertRulesTable do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    create table(:alert_rules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :name, :string, null: false, default: "Untitled"
      add :category, :integer, null: false
      add :metric, :integer, null: false
      add :deviation_percentage, :float, null: false
      add :rolling_window_size, :integer, null: false
      add :slack_channel_id, :string
      add :slack_channel_name, :string

      timestamps(type: :timestamptz)
    end

    create index(:alert_rules, [:project_id])

    create table(:alerts, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :alert_rule_id, references(:alert_rules, type: :uuid, on_delete: :delete_all),
        null: false

      add :current_value, :float, null: false
      add :previous_value, :float, null: false

      timestamps(type: :timestamptz)
    end

    create index(:alerts, [:alert_rule_id])
    create index(:alerts, [:inserted_at])
  end
end
