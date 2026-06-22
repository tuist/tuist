defmodule Tuist.Storage.Workers.DeleteExpiredRunSessionsWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :storage_retention,
    max_attempts: 3,
    unique: [keys: [:account_id, :after_inserted_at, :after_id], states: [:available, :scheduled, :executing, :retryable]]

  import Tuist.Storage.Workers.ExpiredArtifactWorker

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Storage.ExpiredArtifacts

  @default_batch_size 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id} = args}) do
    batch_size = Map.get(args, "batch_size", @default_batch_size)

    case Repo.get(Account, account_id) do
      nil ->
        :ok

      account ->
        account
        |> ExpiredArtifacts.delete_run_sessions(batch_size, cursor_from_args(args))
        |> continue(__MODULE__, account_id, batch_size)
    end
  end
end
