defmodule Tuist.Repo.Migrations.AddRecordedAtToAutomationAlertRevisions do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    alter table(:automation_alert_revisions) do
      add :recorded_at, :timestamptz
    end

    # Existing rows only need their established display timestamp as an ordering baseline.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("UPDATE automation_alert_revisions SET recorded_at = inserted_at")

    alter table(:automation_alert_revisions) do
      # The backfill above guarantees this constraint is valid before it is added.
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      # excellent_migrations:safety-assured-for-next-line not_null_added
      modify :recorded_at, :timestamptz, null: false
    end

    create index(:automation_alert_revisions, [:automation_alert_id, :recorded_at, :id],
             concurrently: true
           )
  end

  def down do
    drop index(:automation_alert_revisions, [:automation_alert_id, :recorded_at, :id],
           concurrently: true
         )

    alter table(:automation_alert_revisions) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :recorded_at
    end
  end
end
