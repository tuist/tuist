defmodule Tuist.Storage.CacheArtifactRetention do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Storage.RetentionPolicy

  @default_page_size 1000
  @artifact_types [:xcode_cache, :xcode_module, :gradle]

  def artifact_types, do: @artifact_types

  def delete_expired(artifact_type, opts \\ []) when artifact_type in @artifact_types do
    target = retention_target(artifact_type)
    bucket_name = Map.fetch!(target, :bucket_name)

    if is_nil(bucket_name) or bucket_name == "" do
      :ok
    else
      page_size = Keyword.get(opts, :page_size, @default_page_size)
      continuation_token = Keyword.get(opts, :continuation_token)

      case Storage.list_objects_from_bucket(bucket_name,
             prefix: "",
             max_keys: page_size,
             continuation_token: continuation_token
           ) do
        {:ok, %{body: body}} ->
          objects = Map.get(body, :contents, [])

          objects_to_delete =
            objects
            |> Enum.filter(&matches_retention_target?(&1, target))
            |> expired_objects(target)

          with :ok <- Storage.delete_objects_from_bucket(Enum.map(objects_to_delete, & &1.key), bucket_name) do
            {:ok, next_continuation_token(body)}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp expired_objects(objects, target) do
    plans_by_account_handle = plans_by_account_handle(objects)
    retention_artifact_type = Map.fetch!(target, :retention_artifact_type)

    Enum.filter(objects, fn object ->
      # An object whose account handle doesn't resolve to a known account is
      # skipped rather than deleted: defaulting to a plan here would apply the
      # shortest (`:air`) retention window and risk purging a paying account's
      # cache early on any handle mismatch. Orphaned blobs from deleted accounts
      # are reclaimed through account deletion, not this job.
      case Map.get(plans_by_account_handle, account_handle(object)) do
        nil ->
          false

        plan ->
          cutoff = RetentionPolicy.cutoff(retention_artifact_type, plan)

          object
          |> last_modified()
          |> expired?(cutoff)
      end
    end)
  end

  defp plans_by_account_handle(objects) do
    account_handles =
      objects
      |> Enum.map(&account_handle/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Account
    |> where([account], account.name in ^account_handles)
    |> Repo.all()
    |> then(fn accounts ->
      # `current_plans/1` batch-loads subscriptions for all fetched accounts,
      # keeping this at two queries per S3 page instead of one query per account.
      plans_by_account_id = RetentionPolicy.current_plans(accounts)

      Map.new(accounts, fn account -> {account.name, Map.fetch!(plans_by_account_id, account.id)} end)
    end)
  end

  defp matches_retention_target?(object, target) do
    expected_path_segment = Map.fetch!(target, :object_path_segment)

    case String.split(object.key, "/", parts: 4) do
      [_account_handle, _project_handle, path_segment, _rest] -> path_segment == expected_path_segment
      _ -> false
    end
  end

  defp account_handle(%{key: key}) do
    case String.split(key, "/", parts: 2) do
      [account_handle, _rest] -> account_handle
      _ -> nil
    end
  end

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

  defp retention_target(:xcode_cache) do
    %{
      bucket_name: Environment.cache_xcode_s3_bucket_name(),
      object_path_segment: "xcode",
      retention_artifact_type: :xcode_cache_artifact
    }
  end

  defp retention_target(:xcode_module) do
    %{
      bucket_name: Environment.cache_s3_bucket_name(),
      object_path_segment: "module",
      retention_artifact_type: :cache_artifact
    }
  end

  defp retention_target(:gradle) do
    %{
      bucket_name: Environment.cache_s3_bucket_name(),
      object_path_segment: "gradle",
      retention_artifact_type: :cache_artifact
    }
  end

  defp next_continuation_token(body) do
    if Map.get(body, :is_truncated) in [true, "true"] do
      Map.get(body, :next_continuation_token)
    end
  end
end
