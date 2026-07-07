defmodule Tuist.Storage.BucketArtifactRetention do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Storage.RetentionPolicy

  @default_page_size 1000
  @delete_receive_timeout 60_000
  @delete_task_timeout 65_000

  def delete_expired(target, opts \\ []) do
    bucket_name = Map.fetch!(target, :bucket_name)

    if is_nil(bucket_name) or bucket_name == "" do
      :ok
    else
      page_size = Keyword.get(opts, :page_size, @default_page_size)
      continuation_token = Keyword.get(opts, :continuation_token)
      prefix = Map.get(target, :prefix, "")
      storage_provider = Map.get(target, :storage_provider, :s3)

      list_opts =
        maybe_put_storage_provider(
          [prefix: prefix, max_keys: page_size, continuation_token: continuation_token],
          storage_provider
        )

      case Storage.list_objects_from_bucket(bucket_name, list_opts) do
        {:ok, %{body: body}} ->
          objects = Map.get(body, :contents, [])

          objects_to_delete =
            objects
            |> Enum.filter(Map.fetch!(target, :object_matches?))
            |> expired_objects(target)

          delete_opts =
            maybe_put_storage_provider(
              [receive_timeout: @delete_receive_timeout, task_timeout: @delete_task_timeout],
              storage_provider
            )

          with :ok <- Storage.delete_objects_from_bucket(Enum.map(objects_to_delete, & &1.key), bucket_name, delete_opts) do
            {:ok, next_continuation_token(body)}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp maybe_put_storage_provider(opts, :s3), do: opts
  defp maybe_put_storage_provider(opts, storage_provider), do: Keyword.put(opts, :storage_provider, storage_provider)

  defp expired_objects(objects, target) do
    plans_by_account_handle = managed_plans_by_account_handle(objects, target)
    retention_artifact_type = Map.fetch!(target, :retention_artifact_type)
    orphaned_account_plan = Map.get(target, :orphaned_account_plan)

    Enum.filter(objects, fn object ->
      plan = plan_for_object(object, plans_by_account_handle) || orphaned_account_plan

      if is_nil(plan) do
        false
      else
        cutoff = RetentionPolicy.cutoff(retention_artifact_type, plan)

        object
        |> last_modified()
        |> expired?(cutoff)
      end
    end)
  end

  defp managed_plans_by_account_handle(objects, target) do
    account_handles =
      objects
      |> Enum.map(&account_handle/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(fn account_handle -> [account_handle, normalize_account_handle(account_handle)] end)
      |> Enum.uniq()

    Account
    |> where([account], account.name in ^account_handles)
    |> Repo.all()
    |> maybe_reject_custom_storage_accounts(target)
    |> then(fn accounts ->
      plans_by_account_id = RetentionPolicy.current_plans(accounts)

      exact_plans_by_account_handle =
        Map.new(accounts, fn account -> {account.name, Map.fetch!(plans_by_account_id, account.id)} end)

      normalized_plans_by_account_handle =
        Map.new(accounts, fn account ->
          {normalize_account_handle(account.name), Map.fetch!(plans_by_account_id, account.id)}
        end)

      Map.merge(normalized_plans_by_account_handle, exact_plans_by_account_handle)
    end)
  end

  defp maybe_reject_custom_storage_accounts(accounts, target) do
    if Map.get(target, :skip_custom_storage_accounts?, false) do
      Enum.reject(accounts, &Account.custom_s3_storage_configured?/1)
    else
      accounts
    end
  end

  defp plan_for_object(object, plans_by_account_handle) do
    account_handle = account_handle(object)

    Map.get(plans_by_account_handle, account_handle) ||
      Map.get(plans_by_account_handle, normalize_account_handle(account_handle))
  end

  defp account_handle(%{key: key}) do
    case String.split(key, "/", parts: 2) do
      [account_handle, _rest] -> account_handle
      _ -> nil
    end
  end

  defp normalize_account_handle(nil), do: nil
  defp normalize_account_handle(account_handle), do: String.downcase(account_handle)

  defp last_modified(%{last_modified: %DateTime{} = last_modified}), do: last_modified

  defp last_modified(%{last_modified: last_modified}) when is_binary(last_modified) do
    case DateTime.from_iso8601(last_modified) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp last_modified(_object), do: nil

  defp expired?(nil, _cutoff), do: false
  defp expired?(last_modified, cutoff), do: DateTime.before?(last_modified, cutoff)

  defp next_continuation_token(body) do
    if Map.get(body, :is_truncated) in [true, "true"] do
      Map.get(body, :next_continuation_token)
    end
  end
end
