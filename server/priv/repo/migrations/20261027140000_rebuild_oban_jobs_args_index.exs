defmodule Tuist.Repo.Migrations.RebuildObanJobsArgsIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # GIN vacuum removes dead postings but retains their entry keys. The
    # production index reached 17.5 GiB, and a bounded page sample found
    # 5,378 of 5,379 entries had no postings. Rebuild the existing definition
    # concurrently to reclaim that history while preserving Oban's lookups.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("REINDEX INDEX CONCURRENTLY oban_jobs_args_index")
  end

  # This changes only physical storage; there is no logical change to undo.
  def down, do: :ok
end
