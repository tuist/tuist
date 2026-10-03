defmodule Atlas.Repo.Migrations.DropInfrastructureAlerts do
  use Ecto.Migration

  def up do
    drop_if_exists table(:infrastructure_alerts)
  end

  def down do
    create table(:infrastructure_alerts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string
      add :source, :string, null: false, default: "grafana"
      add :title, :string, null: false
      add :status, :string, null: false, default: "received"
      add :severity, :string
      add :summary, :text
      add :description, :text
      add :labels, :map, null: false, default: %{}
      add :annotations, :map, null: false, default: %{}
      add :payload, :map, null: false, default: %{}
      add :starts_at, :utc_datetime_usec
      add :ends_at, :utc_datetime_usec
      add :investigation_started_at, :utc_datetime_usec
      add :investigation_finished_at, :utc_datetime_usec
      add :agent_session_id, references(:agent_sessions, type: :binary_id, on_delete: :nilify_all)
      add :report, :text
      add :pull_request_url, :string
      add :error, :text

      timestamps()
    end

    create unique_index(:infrastructure_alerts, [:external_id], where: "external_id IS NOT NULL")

    create index(:infrastructure_alerts, [:status])
    create index(:infrastructure_alerts, [:severity])
    create index(:infrastructure_alerts, [:starts_at])
    create index(:infrastructure_alerts, [:agent_session_id])
  end
end
