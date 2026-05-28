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
    bucket_name = bucket_name(artifact_type)

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
            |> Enum.filter(&matches_artifact_type?(&1, artifact_type))
            |> expired_objects(artifact_type)

          with :ok <- Storage.delete_objects_from_bucket(Enum.map(objects_to_delete, & &1.key), bucket_name) do
            {:ok, next_continuation_token(body)}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp expired_objects(objects, artifact_type) do
    plans_by_account_handle = plans_by_account_handle(objects)

    Enum.filter(objects, fn object ->
      plan =
        object
        |> account_handle()
        |> then(&Map.get(plans_by_account_handle, &1, :air))

      cutoff =
        artifact_type
        |> retention_artifact_type()
        |> RetentionPolicy.cutoff(plan)

      object
      |> last_modified()
      |> expired?(cutoff)
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
    |> Map.new(fn account -> {account.name, RetentionPolicy.current_plan(account)} end)
  end

  defp matches_artifact_type?(object, artifact_type) do
    case String.split(object.key, "/", parts: 4) do
      [_account_handle, _project_handle, "xcode", _rest] -> artifact_type == :xcode_cache
      [_account_handle, _project_handle, "module", _rest] -> artifact_type == :xcode_module
      [_account_handle, _project_handle, "gradle", _rest] -> artifact_type == :gradle
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

  defp retention_artifact_type(:xcode_cache), do: :xcode_cache_artifact
  defp retention_artifact_type(:xcode_module), do: :cache_artifact
  defp retention_artifact_type(:gradle), do: :cache_artifact

  defp bucket_name(:xcode_cache), do: Environment.cache_xcode_s3_bucket_name()
  defp bucket_name(:xcode_module), do: Environment.cache_s3_bucket_name()
  defp bucket_name(:gradle), do: Environment.cache_s3_bucket_name()

  defp next_continuation_token(body) do
    if Map.get(body, :is_truncated) == true do
      Map.get(body, :next_continuation_token)
    end
  end
end
