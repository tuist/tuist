defmodule Tuist.Repo.Migrations.CreateBuildAutomationFindings do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    alter table(:automation_alerts) do
      add :build_scan_state, :map, null: false, default: %{}
    end

    create table(:build_automation_findings, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :alert_id, references(:automation_alerts, type: :uuid, on_delete: :delete_all),
        null: false

      add :source, :text, null: false
      add :unit_id, :text, null: false
      add :evidence, :map, null: false
      add :notified_at, :timestamptz
      add :notification_batch, :uuid
      timestamps(type: :timestamptz)
    end

    create unique_index(:build_automation_findings, [:alert_id, :source, :unit_id],
             concurrently: true
           )

    create index(:build_automation_findings, [:alert_id, :id], concurrently: true)

    create index(:build_automation_findings, [:alert_id, :id],
             name: :build_automation_findings_pending_index,
             where: "notified_at IS NULL",
             concurrently: true
           )
  end
end
