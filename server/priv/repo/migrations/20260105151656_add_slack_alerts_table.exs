defmodule Tuist.Repo.Migrations.AddSlackAlertsTable do
  use Ecto.Migration

  def change do
    create table(:slack_alerts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :category, :integer, null: false
      add :metric, :integer, null: false
      add :threshold_percentage, :float, null: false
      add :sample_size, :integer, null: false
      add :enabled, :boolean, default: true, null: false
      add :slack_channel_id, :string, null: false
      add :slack_channel_name, :string, null: false
      add :last_triggered_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create index(:slack_alerts, [:project_id])
    create index(:slack_alerts, [:enabled])
  end
end
