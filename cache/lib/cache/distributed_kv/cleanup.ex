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

    on_conflict =
      from(pc in ProjectCleanup,
        update: [
          set: [
            cleanup_started_at:
              fragment(
                "CASE WHEN ? > ? THEN ? ELSE EXCLUDED.cleanup_started_at END",
                pc.lease_expires_at,
                ^now,
                pc.cleanup_started_at
              ),
            lease_expires_at:
              fragment(
                "CASE WHEN ? > ? THEN ? ELSE EXCLUDED.lease_expires_at END",
                pc.lease_expires_at,
                ^now,
                pc.lease_expires_at
              ),
            updated_at:
              fragment(
                "CASE WHEN ? > ? THEN ? ELSE EXCLUDED.updated_at END",
                pc.lease_expires_at,
                ^now,
                pc.updated_at
              )
          ]
        ]
      )

    {:ok, result} =
      Repo.insert(
        %ProjectCleanup{
          account_handle: account_handle,
          project_handle: project_handle,
          cleanup_started_at: now,
          lease_expires_at: lease_expires_at,
          updated_at: now
        },
        on_conflict: on_conflict,
        conflict_target: [:account_handle, :project_handle],
        returning: true
      )

    {:ok, result.cleanup_started_at}
  end

  def renew_project_cleanup_lease(account_handle, project_handle, cleanup_started_at) do
    now = DateTime.utc_now()
    lease_expires_at = DateTime.add(now, Config.distributed_kv_cleanup_lease_ms(), :millisecond)

    {count, _} =
      Repo.update_all(
        from(pc in ProjectCleanup,
          where:
            pc.account_handle == ^account_handle and pc.project_handle == ^project_handle and
              pc.cleanup_started_at == ^cleanup_started_at and pc.lease_expires_at > ^now
        ), set: [lease_expires_at: lease_expires_at, updated_at: now])

    if count == 1 do
      :ok
    else
      {:error, :cleanup_lease_lost}
    end
  end

  def tombstone_project_entries(account_handle, project_handle, cleanup_started_at) do
    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(
        from(entry in Entry,
          where: entry.account_handle == ^account_handle,
          where: entry.project_handle == ^project_handle,
          where: entry.source_updated_at <= ^cleanup_started_at,
          where: is_nil(entry.deleted_at)
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
    |> case do
      nil -> nil
      cleanup_started_at -> DateTime.truncate(cleanup_started_at, :second)
    end
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
          {{account_handle, project_handle}, DateTime.truncate(cleanup_started_at, :second)}
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
