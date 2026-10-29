defmodule Atlas.Repo.Migrations.AddDurableTerminalJobs do
  use Ecto.Migration

  def change do
    alter table(:environment_commands) do
      add :environment_name, :text
      add :project_id, :uuid
      add :project_name, :text
      add :execution_timeout_seconds, :integer, null: false, default: 60
      add :execution_deadline, :timestamptz
      add :result_deadline, :timestamptz
      add :cancel_requested, :boolean, null: false, default: false
      add :progress_sequence, :bigint, null: false, default: 0
      add :progress_output, :binary

      add :continuation_message_id,
          references(:orbit_messages, type: :uuid, on_delete: :nilify_all)
    end

    create index(:environment_commands, [:thread_id, :status])
    create index(:environment_commands, [:status, :result_deadline])
    create constraint(:environment_commands, :positive_progress, check: "progress_sequence >= 0")
  end
end
