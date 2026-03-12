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

    Repo.transaction(fn ->
      case Repo.get_by(ProjectCleanup, account_handle: account_handle, project_handle: project_handle) do
        %ProjectCleanup{} = cleanup ->
          if DateTime.after?(cleanup.lease_expires_at, now) do
            cleanup.cleanup_started_at
          else
            attrs = %{
              account_handle: account_handle,
              project_handle: project_handle,
              cleanup_started_at: now,
              lease_expires_at: lease_expires_at,
              updated_at: now
            }

            cleanup
            |> ProjectCleanup.changeset(attrs)
            |> Repo.update!()

            now
          end

        existing ->
          attrs = %{
            account_handle: account_handle,
            project_handle: project_handle,
            cleanup_started_at: now,
            lease_expires_at: lease_expires_at,
            updated_at: now
          }

          changeset = ProjectCleanup.changeset(existing || %ProjectCleanup{}, attrs)

          if existing do
            Repo.update!(changeset)
          else
            Repo.insert!(changeset)
          end

          now
      end
    end)
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

  def purge_tombstones_older_than(days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

    {count, _} =
      Repo.delete_all(from(entry in Entry, where: not is_nil(entry.deleted_at) and entry.deleted_at < ^cutoff))

    count
  end
end
