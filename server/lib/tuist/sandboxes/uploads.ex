defmodule Tuist.Sandboxes.Uploads do
  @moduledoc """
  One-off files a client hands to one of its sandboxes through the account's
  object storage, such as the bundle of `tuist sandbox sync`. A command's
  stdin moves a few MB/s at most, because every write is one exec in the
  guest; a presigned URL lets the client upload at its own bandwidth and the
  guest download at the node's.

  The client PUTs the file to the upload URL and has a command in the sandbox
  GET the download URL. Both URLs expire after an hour, and the object is
  deleted a few minutes after that, whether or not it was used.
  """
  alias Tuist.Accounts.Account
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.DeleteUploadWorker
  alias Tuist.Storage

  @url_ttl_seconds 60 * 60
  @delete_after_seconds @url_ttl_seconds + 5 * 60

  def object_prefix(account_id), do: "sandbox-uploads/#{account_id}/"

  def create(%Account{id: account_id} = account, %Sandbox{account_id: account_id} = sandbox) do
    key = object_prefix(account_id) <> "#{sandbox.id}/#{Ecto.UUID.generate()}"

    {:ok, _job} =
      %{account_id: account_id, key: key}
      |> DeleteUploadWorker.new(schedule_in: @delete_after_seconds)
      |> Oban.insert()

    %{
      upload_url: Storage.generate_upload_url(key, account, expires_in: @url_ttl_seconds),
      download_url: Storage.generate_download_url(key, account, expires_in: @url_ttl_seconds),
      # Whole seconds, like the API's other timestamps: the CLI's generated client rejects fractional ones.
      expires_at: DateTime.add(DateTime.utc_now(:second), @url_ttl_seconds)
    }
  end
end
