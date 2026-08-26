defmodule Tuist.Repo.Migrations.AddRunnerSessionsUpdatedAtIdIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Serves the ClickHouse replication tailer, which pages
  # `runner_sessions` by `(updated_at, id)` every minute and up to
  # twenty times a tick while it is catching up on history. Without it
  # each page is a sequential scan and sort of the table the replica
  # exists to keep analytical reads off.
  #
  # The order matches the keyset the tailer pages on, so the row
  # comparison seeks straight to the cursor instead of filtering.
  def change do
    create index(:runner_sessions, [:updated_at, :id], concurrently: true)
  end
end
