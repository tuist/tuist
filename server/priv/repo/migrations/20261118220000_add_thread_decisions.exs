defmodule Tuist.Repo.Migrations.AddThreadDecisions do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    alter table(:thread_messages) do
      add :decision, :map
    end

    alter table(:thread_runs) do
      # PostgreSQL 16 installs this constant default without rewriting rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :waited_seconds, :bigint, null: false, default: 0
    end

    # Build the stronger constraint before removing the old one, so there is
    # never a window in which a thread can acquire two unfinished runs.
    create unique_index(:thread_runs, [:thread_id],
             where: "status IN ('queued', 'running', 'waiting')",
             name: :thread_runs_one_unfinished,
             concurrently: true
           )

    drop unique_index(:thread_runs, [:thread_id],
           where: "status IN ('queued', 'running')",
           name: :thread_runs_one_active,
           concurrently: true
         )
  end
end
