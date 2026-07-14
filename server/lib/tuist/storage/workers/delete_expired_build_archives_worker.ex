defmodule Tuist.Storage.Workers.DeleteExpiredBuildArchivesWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :storage_retention,
    max_attempts: 3,
    unique: [
      keys: [:account_id],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Tuist.Storage.Workers.ArtifactRetentionWorker
  import Tuist.Storage.Workers.ExpiredArtifactWorker

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Storage.ExpiredArtifacts

  @default_batch_size 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id} = args} = job) do
    batch_size = Map.get(args, "batch_size", @default_batch_size)

    case effective_retention_days(args, :build_archives) do
      {:enabled, retention_days} ->
        case Repo.get(Account, account_id) do
          nil ->
            :ok

          account ->
            account
            |> ExpiredArtifacts.delete_build_archives(batch_size, cursor_from_args(args, retention_days))
            |> continue(job, account_id, batch_size, retention_days, Map.get(args, "self_hosted", false))
        end

      :disabled ->
        :ok
    end
  end
end
