defmodule Tuist.Storage.Workers.ScheduleExpiredArtifactsWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :storage_retention,
    max_attempts: 3,
    unique: [
      fields: [:queue, :worker],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Storage.Workers.ArtifactRetentionWorker
  alias Tuist.Storage.Workers.DeleteExpiredBuildArchivesWorker
  alias Tuist.Storage.Workers.DeleteExpiredPreviewArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredRunSessionsWorker
  alias Tuist.Storage.Workers.DeleteExpiredShardBundlesWorker
  alias Tuist.Storage.Workers.DeleteExpiredTestAttachmentsWorker

  @default_page_size 500
  @deletion_workers [
    {"app_previews", DeleteExpiredPreviewArtifactsWorker},
    {"build_archives", DeleteExpiredBuildArchivesWorker},
    {"run_artifacts", DeleteExpiredRunSessionsWorker},
    {"test_attachments", DeleteExpiredTestAttachmentsWorker},
    {"shard_bundles", DeleteExpiredShardBundlesWorker}
  ]

  def deletion_workers, do: Enum.map(@deletion_workers, fn {_resource_type, worker} -> worker end)

  def deletion_workers(retention_days) when is_map(retention_days) do
    @deletion_workers
    |> Enum.filter(fn {resource_type, _worker} -> Map.has_key?(retention_days, resource_type) end)
    |> Enum.map(fn {_resource_type, worker} -> worker end)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    batch_size = Map.get(args, "batch_size")
    page_size = Map.get(args, "page_size", @default_page_size)
    after_id = Map.get(args, "after_id", 0)
    self_hosted = Map.get(args, "self_hosted", false)
    retention_days = effective_retention_days(Map.get(args, "retention_days"), self_hosted)

    if self_hosted and deletion_workers(retention_days) == [] do
      :ok
    else
      schedule_account_page(%{
        batch_size: batch_size,
        page_size: page_size,
        after_id: after_id,
        retention_days: retention_days,
        self_hosted: self_hosted,
        job: job
      })
    end
  end

  defp schedule_account_page(%{
         batch_size: batch_size,
         page_size: page_size,
         after_id: after_id,
         retention_days: retention_days,
         self_hosted: self_hosted,
         job: job
       }) do
    account_ids =
      Account
      |> where([account], account.id > ^after_id)
      |> order_by([account], asc: account.id)
      |> limit(^(page_size + 1))
      |> select([account], account.id)
      |> Repo.all()

    {account_ids, next_account_ids} = Enum.split(account_ids, page_size)

    deletion_jobs =
      Enum.flat_map(account_ids, fn account_id ->
        Enum.map(configured_deletion_workers(retention_days), fn {deletion_worker, days} ->
          %{"account_id" => account_id}
          |> maybe_put_batch_size(batch_size)
          |> maybe_put_retention_days(days)
          |> maybe_put_self_hosted(self_hosted)
          |> deletion_worker.new()
        end)
      end)

    with :ok <- insert_deletion_jobs(deletion_jobs, self_hosted) do
      schedule_next_account_page(next_account_ids, account_ids, page_size, batch_size, retention_days, self_hosted, job)
    end
  end

  defp insert_deletion_jobs([], _self_hosted), do: :ok

  defp insert_deletion_jobs(jobs, false) do
    Oban.insert_all(jobs)
    :ok
  end

  defp insert_deletion_jobs(jobs, true) do
    # Oban's basic engine doesn't enforce worker uniqueness for bulk inserts.
    Enum.reduce_while(jobs, :ok, fn job, :ok ->
      case Oban.insert(job) do
        {:ok, _job} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp schedule_next_account_page([], _account_ids, _page_size, _batch_size, _retention_days, _self_hosted, _job), do: :ok

  defp schedule_next_account_page(_next_account_ids, account_ids, page_size, batch_size, retention_days, self_hosted, job) do
    args =
      %{"after_id" => List.last(account_ids), "page_size" => page_size}
      |> maybe_put_batch_size(batch_size)
      |> maybe_put_retention_config(retention_days)
      |> maybe_put_self_hosted(self_hosted)

    ArtifactRetentionWorker.reschedule_with_args(job, args)
  end

  defp maybe_put_batch_size(args, nil), do: args
  defp maybe_put_batch_size(args, batch_size), do: Map.put(args, "batch_size", batch_size)

  defp maybe_put_retention_days(args, nil), do: args
  defp maybe_put_retention_days(args, retention_days), do: Map.put(args, "retention_days", retention_days)

  defp maybe_put_retention_config(args, nil), do: args
  defp maybe_put_retention_config(args, retention_days), do: Map.put(args, "retention_days", retention_days)

  defp maybe_put_self_hosted(args, false), do: args
  defp maybe_put_self_hosted(args, true), do: Map.put(args, "self_hosted", true)

  defp configured_deletion_workers(nil) do
    Enum.map(@deletion_workers, fn {_resource_type, worker} -> {worker, nil} end)
  end

  defp configured_deletion_workers(retention_days) do
    Enum.flat_map(@deletion_workers, fn {resource_type, worker} ->
      case Map.fetch(retention_days, resource_type) do
        {:ok, days} -> [{worker, days}]
        :error -> []
      end
    end)
  end

  defp effective_retention_days(_retention_days, true) do
    Map.new(Environment.artifact_retention_days(), fn {resource_type, days} -> {Atom.to_string(resource_type), days} end)
  end

  defp effective_retention_days(retention_days, false), do: retention_days
end
