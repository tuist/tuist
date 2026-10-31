defmodule Tuist.Accounts.Workers.DeleteAccountArtifactsWorker do
  @moduledoc """
  Erases artifact objects after account deletion, including uploads never committed
  as publications. Enqueued in the deletion transaction, so cleanup cannot be lost
  when a node stops after deleting the account.

  Only the minimal storage actor is retained, encrypted like queued confirmation
  URLs. It must survive the account row and remain decryptable for manual retries.
  """
  use Oban.Worker, queue: :storage_retention, max_attempts: 3

  alias Tuist.Accounts.Account
  alias Tuist.Artifacts
  alias Tuist.Artifacts.Package
  alias Tuist.Storage
  alias Tuist.Storage.Workers.ArtifactRetentionWorker

  @storage_salt "deleted-account-artifact-storage"
  @storage_fields [:id, :name, :s3_bucket_name, :s3_access_key_id, :s3_secret_access_key, :s3_region, :s3_endpoint]

  def new_cleanup(%Account{} = account) do
    storage_actor = Map.take(account, @storage_fields)
    encrypted_storage = Phoenix.Token.encrypt(Tuist.Web.endpoint(), @storage_salt, storage_actor)
    new(%{account_id: account.id, encrypted_storage: encrypted_storage})
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "encrypted_storage" => encrypted_storage} = args} = job) do
    # No new upload can be admitted after account deletion. If a writer existed
    # at the start of this pass, rescan from the beginning even if it settles
    # behind our pagination cursor. Lost writers deliberately keep cleanup live.
    args =
      if args["continuation_token"],
        do: args,
        else: Map.put(args, "writers_present", Artifacts.uploads_pending?(account_id))

    with {:ok, %{id: ^account_id} = storage_actor} <-
           Phoenix.Token.decrypt(Tuist.Web.endpoint(), @storage_salt, encrypted_storage, max_age: :infinity),
         account = struct(Account, storage_actor),
         {:ok, %{body: body}} <-
           Storage.list_objects("#{account.id}/", account,
             max_keys: 500,
             continuation_token: args["continuation_token"]
           ),
         keys = artifact_keys(Map.get(body, :contents, []), account.id),
         :ok <- Storage.delete_objects(keys, account) do
      cond do
        Map.get(body, :is_truncated) in [true, "true"] ->
          reschedule(
            job,
            Map.put(args, "continuation_token", body.next_continuation_token),
            0
          )

        args["writers_present"] ->
          reschedule(job, Map.delete(args, "continuation_token"), 30)

        true ->
          :ok
      end
    else
      # Never exhaust the erasure obligation or persist credential-bearing errors.
      # Oban snoozing preserves the snapshot and extends the execution budget.
      _ -> {:snooze, 300}
    end
  rescue
    _ -> {:snooze, 300}
  end

  defp reschedule(job, args, delay) do
    case ArtifactRetentionWorker.reschedule_with_args(job, args) do
      {:snooze, 0} -> {:snooze, delay}
      _ -> {:snooze, 300}
    end
  end

  defp artifact_keys(objects, account_id) do
    account_prefix = to_string(account_id)

    objects
    |> Enum.filter(fn %{key: object_key} ->
      case String.split(object_key, "/") do
        [^account_prefix, project_id, "artifacts", key, digest] ->
          String.match?(project_id, ~r/\A[1-9][0-9]*\z/) and Package.valid_digest?(key) and Package.valid_digest?(digest)

        _ ->
          false
      end
    end)
    |> Enum.map(& &1.key)
  end
end
