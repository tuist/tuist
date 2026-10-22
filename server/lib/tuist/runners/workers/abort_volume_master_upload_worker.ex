defmodule Tuist.Runners.Workers.AbortVolumeMasterUploadWorker do
  @moduledoc """
  Aborts a cache volume master's multipart upload once its links expired.

  `Tuist.Runners.start_volume_master_upload/4` enqueues this for every upload.
  Aborting an upload that completed is a no-op, so completion never cancels
  it. An account deleted in the meantime has no storage to resolve and is
  skipped.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Accounts
  alias Tuist.Storage

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "object_key" => object_key, "upload_id" => upload_id}}) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:error, reason} = error <- Storage.multipart_abort(object_key, upload_id, account) do
      Logger.warning("runners: cache volume master upload abort failed for #{object_key}: #{inspect(reason)}")
      error
    else
      _ -> :ok
    end
  end
end
