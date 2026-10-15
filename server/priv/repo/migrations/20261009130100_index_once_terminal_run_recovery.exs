defmodule Tuist.Repo.Migrations.IndexOnceTerminalRunRecovery do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:once_runs, [:finalized_at, :id],
             name: :once_runs_terminal_recovery_index,
             where: "finalization IN ('finalized', 'lost')",
             concurrently: true
           )
  end
end
