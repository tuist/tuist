defmodule Tuist.Runners.Workers.PurgeBuiltinVolumeMastersWorker do
  @moduledoc """
  Deletes an account's built-in runner cache masters from object storage: the
  keys under `runner-volume-masters/<account_id>/` whose volume segment is
  `tuist-cache` or `repo-<16 hex>`, plus the legacy `tuist-cache.zip`. Custom
  volume keys (`macos-` and `linux-`) are never touched. Idempotent.
  """
  use Oban.Worker, queue: :default, max_attempts: 20

  alias Tuist.Accounts
  alias Tuist.Runners
  alias Tuist.Storage

  @page_size 1000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    case Accounts.get_account_by_id(account_id) do
      {:ok, account} -> purge(account, Runners.volume_master_object_prefix(account_id), nil)
      {:error, :not_found} -> :ok
    end
  end

  defp purge(account, prefix, continuation_token) do
    with {:ok, %{body: body}} <-
           Storage.list_objects(prefix, account, max_keys: @page_size, continuation_token: continuation_token),
         keys = body |> Map.get(:contents, []) |> Enum.map(& &1.key) |> Enum.filter(&builtin_key?(&1, prefix)),
         :ok <- Storage.delete_objects(keys, account) do
      case next_continuation_token(body) do
        nil -> :ok
        token -> purge(account, prefix, token)
      end
    end
  end

  defp builtin_key?(key, prefix) do
    case String.replace_prefix(key, prefix, "") do
      "tuist-cache.zip" -> true
      "tuist-cache/" <> _ -> true
      "repo-" <> rest -> Regex.match?(~r/\A[0-9a-f]{16}\//, rest)
      _ -> false
    end
  end

  defp next_continuation_token(body) do
    if Map.get(body, :is_truncated) in [true, "true"] do
      Map.get(body, :next_continuation_token)
    end
  end
end
