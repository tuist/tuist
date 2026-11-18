defmodule Atlas.Repo.Migrations.RemoveTaskReminders do
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM oban_jobs
    WHERE worker IN (
      'Elixir.Atlas.Tasks.Workers.SendReminder',
      'Elixir.Atlas.Tasks.Workers.SendDueDate'
    )
    """)

    drop index(:tasks, [:assignee_id, :status, :remind_at])

    alter table(:tasks) do
      remove :remind_at
      remove :reminded_at
      remove :reminder_version
      remove :due_notified_at
      remove :due_version
    end
  end

  def down do
    alter table(:tasks) do
      add :remind_at, :timestamptz
      add :reminded_at, :timestamptz
      add :reminder_version, :integer, null: false, default: 1
      add :due_notified_at, :timestamptz
      add :due_version, :integer, null: false, default: 1
    end

    create index(:tasks, [:assignee_id, :status, :remind_at])
  end
end
