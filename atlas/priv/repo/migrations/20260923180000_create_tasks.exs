defmodule Atlas.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "open"
      add :due_on, :date
      add :remind_at, :timestamptz
      add :reminded_at, :timestamptz
      add :reminder_version, :integer, null: false, default: 1
      add :due_notified_at, :timestamptz
      add :due_version, :integer, null: false, default: 1
      add :completed_at, :timestamptz
      add :assignee_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    create constraint(:tasks, :tasks_status_check, check: "status IN ('open', 'completed')")
    create index(:tasks, [:assignee_id, :status, :remind_at])
    create index(:tasks, [:account_id, :status])
  end
end
