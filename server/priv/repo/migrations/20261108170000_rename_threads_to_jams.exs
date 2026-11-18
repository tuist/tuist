# Internal feature: stop its old workers and coordinate server/client upgrades.
# The in-place rename preserves history; see data-export.md for the rollout boundary.
# SQL updates only this feature's worker and sandbox identity namespaces.
# excellent_migrations:safety-assured-for-this-file table_renamed column_renamed raw_sql_executed
defmodule Tuist.Repo.Migrations.RenameThreadsToJams do
  use Ecto.Migration

  @tables [
    {:threads, :jams},
    {:thread_messages, :jam_messages},
    {:thread_ship_approvals, :jam_ship_approvals},
    {:thread_runs, :jam_runs},
    {:thread_tool_calls, :jam_tool_calls},
    {:thread_inboxes, :jam_inboxes}
  ]

  def up do
    for {old, new} <- @tables, do: rename(table(old), to: table(new))

    for name <- [:jam_messages, :jam_ship_approvals, :jam_runs] do
      rename table(name), :thread_id, to: :jam_id
    end

    execute """
    UPDATE oban_jobs
    SET worker = replace(worker, 'Tuist.Threads.', 'Tuist.Jams.'),
        queue = CASE WHEN queue = 'threads' THEN 'jams' ELSE queue END
    WHERE worker LIKE 'Tuist.Threads.%'
    """

    execute """
    UPDATE sandbox_provider_environments
    SET external_key = 'jams/' || substring(external_key from 9)
    WHERE external_key LIKE 'threads/%'
    """

    execute """
    UPDATE sandboxes
    SET residency_work_id = 'jams' || substring(residency_work_id from 8)
    WHERE residency_work_id LIKE 'threads:%' OR residency_work_id LIKE 'threads-ship:%'
    """
  end

  def down do
    execute """
    UPDATE sandboxes
    SET residency_work_id = 'threads' || substring(residency_work_id from 5)
    WHERE residency_work_id LIKE 'jams:%' OR residency_work_id LIKE 'jams-ship:%'
    """

    execute """
    UPDATE sandbox_provider_environments
    SET external_key = 'threads/' || substring(external_key from 6)
    WHERE external_key LIKE 'jams/%'
    """

    execute """
    UPDATE oban_jobs
    SET worker = replace(worker, 'Tuist.Jams.', 'Tuist.Threads.'),
        queue = CASE WHEN queue = 'jams' THEN 'threads' ELSE queue END
    WHERE worker LIKE 'Tuist.Jams.%'
    """

    for name <- [:jam_messages, :jam_ship_approvals, :jam_runs] do
      rename table(name), :jam_id, to: :thread_id
    end

    for {old, new} <- Enum.reverse(@tables), do: rename(table(new), to: table(old))
  end
end
