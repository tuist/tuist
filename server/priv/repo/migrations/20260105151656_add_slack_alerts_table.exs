defmodule Tuist.Repo.Migrations.AddAlertRulesTable do
  use Ecto.Migration

  def change do
    create table(:alert_rules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :category, :integer, null: false
      add :metric, :integer, null: false
      add :deviation_percentage, :float, null: false
      add :rolling_window_size, :integer, null: false
      add :slack_channel_id, :string
      add :slack_channel_name, :string
      add :last_triggered_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create index(:alert_rules, [:project_id])
  end
end
