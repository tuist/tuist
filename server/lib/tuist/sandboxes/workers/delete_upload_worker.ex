defmodule Tuist.Sandboxes.Workers.DeleteUploadWorker do
  @moduledoc """
  Deletes a sandbox upload (`Tuist.Sandboxes.Uploads`) once its URLs have
  expired.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "key" => key}}) do
    case Repo.get(Account, account_id) do
      # The account's deletion purged its storage.
      nil -> :ok
      account -> Storage.delete_object(key, account)
    end
  end
end
