defmodule Tuist.Repo.Migrations.IndexOnceActionHistory do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Project/history scope plus timestamp and UUID provide deterministic history pagination.
    # excellent_migrations:safety-assured-for-next-line many_columns_index
    create index(:once_actions, [:project_id, :history_id, :started_at, :id],
             concurrently: true,
             where: "history_id IS NOT NULL AND NOT history_ambiguous",
             name: :once_actions_history_occurrences_index
           )

    create index(:once_actions, [:once_run_id, :history_id],
             concurrently: true,
             where: "history_id IS NOT NULL",
             name: :once_actions_run_history_identity_index
           )
  end
end
