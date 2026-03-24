defmodule Cache.DistributedKV.Cleanup do
  @moduledoc false

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Project
  alias Cache.DistributedKV.Repo

  def begin_project_cleanup(account_handle, project_handle) do
    now = DateTime.utc_now()
    cleanup_lease_expires_at = DateTime.add(now, Config.distributed_kv_cleanup_lease_ms(), :millisecond)

    on_conflict =
      from(project in Project,
        where: project.cleanup_lease_expires_at <= ^now,
        update: [
          set: [
            last_cleanup_at: ^now,
            cleanup_lease_expires_at: ^cleanup_lease_expires_at,
            updated_at: ^now
          ]
        ]
      )

    case Repo.insert_all(
           Project,
           [
             %{
               account_handle: account_handle,
               project_handle: project_handle,
               last_cleanup_at: now,
               cleanup_lease_expires_at: cleanup_lease_expires_at,
               updated_at: now
             }
           ],
           on_conflict: on_conflict,
           conflict_target: [:account_handle, :project_handle],
           returning: [:last_cleanup_at]
         ) do
      {1, [%{last_cleanup_at: last_cleanup_at}]} -> {:ok, last_cleanup_at}
      {0, []} -> {:error, :cleanup_already_in_progress}
    end
  end

  def renew_project_cleanup_lease(account_handle, project_handle, cleanup_started_at) do
    now = DateTime.utc_now()
    cleanup_lease_expires_at = DateTime.add(now, Config.distributed_kv_cleanup_lease_ms(), :millisecond)

    {count, _} =
      Repo.update_all(
        from(project in Project,
          where:
            project.account_handle == ^account_handle and project.project_handle == ^project_handle and
              project.last_cleanup_at == ^cleanup_started_at and project.cleanup_lease_expires_at > ^now
        ),
        set: [cleanup_lease_expires_at: cleanup_lease_expires_at, updated_at: now]
      )

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
    Project
    |> where([project], project.account_handle == ^account_handle)
    |> where([project], project.project_handle == ^project_handle)
    |> select([project], project.last_cleanup_at)
    |> Repo.one()
    |> case do
      nil -> nil
      last_cleanup_at -> DateTime.truncate(last_cleanup_at, :second)
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

        Project
        |> where(^scope_filter)
        |> select([project], {project.account_handle, project.project_handle, project.last_cleanup_at})
        |> Repo.all()
        |> Map.new(fn {account_handle, project_handle, last_cleanup_at} ->
          {{account_handle, project_handle}, DateTime.truncate(last_cleanup_at, :second)}
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
