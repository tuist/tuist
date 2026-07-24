defmodule Tuist.Repo.Migrations.CreateAutomationAlertRevisions do
  use Ecto.Migration

  def change do
    create table(:automation_alert_revisions, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :automation_alert_id,
          references(:automation_alerts, type: :uuid, on_delete: :delete_all), null: false

      add :actor_id, references(:users, on_delete: :nilify_all)
      add :event, :string, null: false
      add :source, :string, null: false, default: "system"
      add :changes, :map, null: false, default: %{}
      add :snapshot, :map, null: false, default: %{}

      timestamps(updated_at: false, type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:automation_alert_revisions, [:automation_alert_id, :inserted_at])
  end
end
