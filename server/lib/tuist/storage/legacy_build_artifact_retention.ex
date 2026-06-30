defmodule Tuist.Storage.LegacyBuildArtifactRetention do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Storage.RetentionPolicy

  @default_page_size 1000
  @delete_receive_timeout 60_000
  @delete_task_timeout 65_000
  @orphaned_account_plan :air
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  def delete_expired(opts \\ []) do
    bucket_name = Environment.s3_bucket_name()

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
            |> Enum.filter(&legacy_build_artifact?/1)
            |> expired_objects()

          delete_opts = [receive_timeout: @delete_receive_timeout, task_timeout: @delete_task_timeout]

          with :ok <- Storage.delete_objects_from_bucket(Enum.map(objects_to_delete, & &1.key), bucket_name, delete_opts) do
            {:ok, next_continuation_token(body)}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp legacy_build_artifact?(object) do
    case String.split(object.key, "/", parts: 6) do
      [_account_handle, _project_handle, "builds", build_identifier, "build.zip"] ->
        not Regex.match?(@uuid_pattern, build_identifier)

      [_account_handle, _project_handle, "builds", _build_identifier, _object_name] ->
        true

      [_account_handle, _project_handle, "builds", _build_identifier, _object_name, _rest] ->
        true

      _ ->
        false
    end
  end

  defp expired_objects(objects) do
    plans_by_account_handle = managed_plans_by_account_handle(objects)

    Enum.filter(objects, fn object ->
      plan = plan_for_object(object, plans_by_account_handle) || @orphaned_account_plan
      cutoff = RetentionPolicy.cutoff(:build_archive, plan)

      object
      |> last_modified()
      |> expired?(cutoff)
    end)
  end

  defp managed_plans_by_account_handle(objects) do
    account_handles =
      objects
      |> Enum.map(&account_handle/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(fn account_handle -> [account_handle, normalize_account_handle(account_handle)] end)
      |> Enum.uniq()

    Account
    |> where([account], account.name in ^account_handles)
    |> Repo.all()
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
