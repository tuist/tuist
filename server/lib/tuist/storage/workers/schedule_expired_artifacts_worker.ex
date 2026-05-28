defmodule Tuist.Storage.Workers.ScheduleExpiredArtifactsWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:after_id], states: [:available, :scheduled, :executing, :retryable]]

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Storage.Workers.DeleteExpiredBuildArchivesWorker
  alias Tuist.Storage.Workers.DeleteExpiredPreviewArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredShardBundlesWorker
  alias Tuist.Storage.Workers.DeleteExpiredTestAttachmentsWorker

  @default_page_size 500
  @deletion_workers [
    DeleteExpiredPreviewArtifactsWorker,
    DeleteExpiredBuildArchivesWorker,
    DeleteExpiredTestAttachmentsWorker,
    DeleteExpiredShardBundlesWorker
  ]

  def deletion_workers, do: @deletion_workers

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    batch_size = Map.get(args, "batch_size")
    page_size = Map.get(args, "page_size", @default_page_size)
    after_id = Map.get(args, "after_id", 0)

    schedule_account_page(%{batch_size: batch_size, page_size: page_size, after_id: after_id})

    :ok
  end

  defp schedule_account_page(%{batch_size: batch_size, page_size: page_size, after_id: after_id}) do
    account_ids =
      Account
      |> where([account], account.id > ^after_id)
      |> order_by([account], asc: account.id)
      |> limit(^(page_size + 1))
      |> select([account], account.id)
      |> Repo.all()

    {account_ids, next_account_ids} = Enum.split(account_ids, page_size)

    account_ids
    |> Enum.flat_map(fn account_id ->
      Enum.map(@deletion_workers, fn deletion_worker ->
        %{"account_id" => account_id}
        |> maybe_put_batch_size(batch_size)
        |> deletion_worker.new()
      end)
    end)
    |> insert_all()

    if next_account_ids != [] do
      %{"after_id" => List.last(account_ids), "page_size" => page_size}
      |> maybe_put_batch_size(batch_size)
      |> __MODULE__.new()
      |> Oban.insert()
    end
  end

  defp insert_all([]), do: :ok
  defp insert_all(jobs), do: Oban.insert_all(jobs)

  defp maybe_put_batch_size(args, nil), do: args
  defp maybe_put_batch_size(args, batch_size), do: Map.put(args, "batch_size", batch_size)
end
