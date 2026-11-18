# Stop feature workers and coordinate the schema migration with the server upgrade.
# Existing branches and approval targets are retained, not renamed in Git.
# excellent_migrations:safety-assured-for-this-file table_renamed column_renamed raw_sql_executed
defmodule Tuist.Repo.Migrations.RenameJamsToThreads do
  use Ecto.Migration

  @tables [
    {:jams, :threads},
    {:jam_messages, :thread_messages},
    {:jam_ship_approvals, :thread_ship_approvals},
    {:jam_runs, :thread_runs},
    {:jam_tool_calls, :thread_tool_calls},
    {:jam_inboxes, :thread_inboxes}
  ]

  def up do
    for {old, new} <- @tables, do: rename(table(old), to: table(new))

    for name <- [:thread_messages, :thread_ship_approvals, :thread_runs] do
      rename table(name), :jam_id, to: :thread_id
    end

    execute """
    UPDATE oban_jobs
    SET worker = replace(worker, 'Tuist.Jams.', 'Tuist.Threads.'),
        queue = CASE WHEN queue = 'jams' THEN 'threads' ELSE queue END
    WHERE worker LIKE 'Tuist.Jams.%'
    """

    execute """
    UPDATE sandbox_provider_environments
    SET external_key = 'threads/' || substring(external_key from 6)
    WHERE external_key LIKE 'jams/%'
    """

    execute """
    UPDATE sandboxes
    SET residency_work_id = 'threads' || substring(residency_work_id from 5)
    WHERE residency_work_id LIKE 'jams:%' OR residency_work_id LIKE 'jams-ship:%'
    """
  end

  def down do
    execute """
    UPDATE sandboxes
    SET residency_work_id = 'jams' || substring(residency_work_id from 8)
    WHERE residency_work_id LIKE 'threads:%' OR residency_work_id LIKE 'threads-ship:%'
    """

    execute """
    UPDATE sandbox_provider_environments
    SET external_key = 'jams/' || substring(external_key from 9)
    WHERE external_key LIKE 'threads/%'
    """

    execute """
    UPDATE oban_jobs
    SET worker = replace(worker, 'Tuist.Threads.', 'Tuist.Jams.'),
        queue = CASE WHEN queue = 'threads' THEN 'jams' ELSE queue END
    WHERE worker LIKE 'Tuist.Threads.%'
    """

    for name <- [:thread_messages, :thread_ship_approvals, :thread_runs] do
      rename table(name), :thread_id, to: :jam_id
    end

    for {old, new} <- Enum.reverse(@tables), do: rename(table(new), to: table(old))
  end
end
