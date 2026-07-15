defmodule Tuist.Repo.Migrations.CreateRunnerJobCompletions do
  use Ecto.Migration

  def change do
    create table(:runner_job_completions, primary_key: false) do
      add :workflow_job_id, :bigint, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :conclusion, :string, null: false
      add :completed_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_job_completions, [:account_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_job_completions, [:completed_at])
  end
end
