defmodule Cache.DistributedKV.Cleanup do
  @moduledoc false

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.ProjectCleanup
  alias Cache.DistributedKV.Repo

  def begin_project_cleanup(account_handle, project_handle) do
    now = DateTime.utc_now()
    lease_expires_at = DateTime.add(now, Config.distributed_kv_cleanup_lease_ms(), :millisecond)

    result =
      Repo.query!(
        """
        INSERT INTO distributed_kv_project_cleanups (
          account_handle,
          project_handle,
          cleanup_started_at,
          lease_expires_at,
          updated_at
        )
        VALUES ($1, $2, $3, $4, $3)
        ON CONFLICT (account_handle, project_handle) DO UPDATE
        SET
          cleanup_started_at = CASE
            WHEN distributed_kv_project_cleanups.lease_expires_at > $3
              THEN distributed_kv_project_cleanups.cleanup_started_at
            ELSE EXCLUDED.cleanup_started_at
          END,
          lease_expires_at = CASE
            WHEN distributed_kv_project_cleanups.lease_expires_at > $3
              THEN distributed_kv_project_cleanups.lease_expires_at
            ELSE EXCLUDED.lease_expires_at
          END,
          updated_at = CASE
            WHEN distributed_kv_project_cleanups.lease_expires_at > $3
              THEN distributed_kv_project_cleanups.updated_at
            ELSE EXCLUDED.updated_at
          END
        RETURNING cleanup_started_at
        """,
        [account_handle, project_handle, now, lease_expires_at],
        timeout: Config.distributed_kv_database_timeout_ms()
      )

    [[cleanup_started_at]] = result.rows
    {:ok, cleanup_started_at}
  end

  def tombstone_project_entries(account_handle, project_handle, cleanup_started_at) do
    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(
        from(entry in Entry,
          where: entry.account_handle == ^account_handle,
          where: entry.project_handle == ^project_handle,
          where: entry.source_updated_at <= ^cleanup_started_at
        ),
        set: [deleted_at: cleanup_started_at, updated_at: now]
      )

    count
  end

  def latest_project_cleanup_cutoff(account_handle, project_handle) do
    ProjectCleanup
    |> where([cleanup], cleanup.account_handle == ^account_handle)
    |> where([cleanup], cleanup.project_handle == ^project_handle)
    |> select([cleanup], cleanup.cleanup_started_at)
    |> Repo.one()
  end

  def latest_project_cleanup_cutoffs(scopes) do
    scope_pairs =
      scopes
      |> Enum.map(&{&1.account_handle, &1.project_handle})
      |> Enum.uniq()

    case scope_pairs do
      [] ->
        %{}

      _ ->
        scope_filter =
          Enum.reduce(scope_pairs, dynamic(false), fn {account_handle, project_handle}, dynamic ->
            dynamic(
              [cleanup],
              ^dynamic or
                (cleanup.account_handle == ^account_handle and cleanup.project_handle == ^project_handle)
            )
          end)

        ProjectCleanup
        |> where(^scope_filter)
        |> select([cleanup], {cleanup.account_handle, cleanup.project_handle, cleanup.cleanup_started_at})
        |> Repo.all()
        |> Map.new(fn {account_handle, project_handle, cleanup_started_at} ->
          {{account_handle, project_handle}, cleanup_started_at}
        end)
    end
  end

  def purge_tombstones_older_than(days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

    {count, _} =
      Repo.delete_all(from(entry in Entry, where: not is_nil(entry.deleted_at) and entry.deleted_at < ^cutoff))

    count
  end
end
