defmodule Atlas.Repo.Migrations.CreateAlertRules do
  use Ecto.Migration

  def change do
    create table(:alert_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, size: 200, null: false
      add :source, :string, size: 32, null: false, default: "error_issue"
      add :trigger, :string, size: 32, null: false
      add :tier, :string, size: 16, null: false, default: "attention"
      add :enabled, :boolean, null: false, default: true
      add :threshold_event_count, :integer
      add :min_level, :string, size: 16
      add :environment, :string, size: 200
      add :cooldown_minutes, :integer, null: false, default: 60
      add :destination_type, :string, size: 16, null: false, default: "slack"
      add :slack_channel_id, :string, size: 80
      add :slack_mention, :string, size: 16
      add :webhook_url, :text
      add :webhook_signing_secret, :string, size: 128

      timestamps(type: :timestamptz)
    end

    create index(:alert_rules, [:project_id, :enabled])
    create index(:alert_rules, [:source, :enabled])
    create index(:alert_rules, [:destination_type])

    create table(:alert_notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :rule_id, references(:alert_rules, type: :binary_id, on_delete: :delete_all),
        null: false

      add :subject_type, :string, size: 32, null: false
      add :subject_id, :binary_id, null: false
      add :status, :string, size: 16, null: false
      add :fired_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}
      add :last_error, :text

      timestamps(type: :timestamptz)
    end

    create index(:alert_notifications, [:rule_id, :subject_id, :fired_at])
  end
end
