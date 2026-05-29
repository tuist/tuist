defmodule Tuist.Storage.Workers.DeleteExpiredBuildArchivesWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :storage_retention,
    max_attempts: 3,
    unique: [keys: [:account_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Storage.ExpiredArtifacts

  @default_batch_size 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id} = args}) do
    batch_size = Map.get(args, "batch_size", @default_batch_size)

    case Repo.get(Account, account_id) do
      nil -> :ok
      account -> ExpiredArtifacts.delete_build_archives(account, batch_size)
    end

    :ok
  end
end
