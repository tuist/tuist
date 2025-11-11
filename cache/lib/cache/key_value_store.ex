defmodule Cache.KeyValueStore do
  @moduledoc """
  Read-through key-value cache backed by Cachex and persisted to SQLite.
  Provides pre-serialized payloads to minimize response rendering time.
  """

  import Cachex.Spec, only: [expiration: 1]

  alias Cache.KeyValueEntry
  alias Cache.Repo

  @cache_name :cache_keyvalue_store
  # 1 week
  @ttl_ms to_timeout(week: 1)

  @doc """
  Starts the cache with the configured settings.
  Should be called from the application supervisor.
  """
  def start_link(_opts) do
    Cachex.start_link(@cache_name, cache_options())
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @doc """
  Stores an array of values for a given CAS ID, account, and project.
  Overwrites any existing values.
  """

  def put_key_value(cas_id, account_handle, project_handle, values) when is_list(values) do
    key = build_key(account_handle, project_handle, cas_id)
    json = encode_entries(values)

    with :ok <- persist_entry(key, json),
         {:ok, _} <- Cachex.put(@cache_name, key, json) do
      :ok
    end
  end

  @doc """
  Retrieves the pre-encoded JSON payload for a given CAS ID, account, and project.
  Returns `{:error, :not_found}` if no entry is stored.
  """
  def get_key_value(cas_id, account_handle, project_handle) do
    key = build_key(account_handle, project_handle, cas_id)

    case fetch_entry(key) do
      {:ok, json} -> {:ok, json}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp cache_options do
    [
      stats: false,
      expiration: expiration(default: @ttl_ms, interval: to_timeout(minute: 5)),
      backend_options: [read_concurrency: true, write_concurrency: true]
    ]
  end

  defp fetch_entry(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} ->
        load_from_persistence(key)

      {:ok, json} when is_binary(json) ->
        {:ok, json}

      {:ok, _} ->
        {:error, :not_found}

      {:error, _} ->
        load_from_persistence(key)
    end
  end

  defp persist_entry(key, json) do
    attrs = %{
      key: key,
      json_payload: json
    }

    %KeyValueEntry{}
    |> KeyValueEntry.changeset(attrs)
    |> Repo.insert(
      conflict_target: :key,
      on_conflict: {:replace, [:json_payload, :updated_at]}
    )
    |> case do
      {:ok, _record} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_from_persistence(key) do
    case Repo.get_by(KeyValueEntry, key: key) do
      nil ->
        {:error, :not_found}

      record ->
        Cachex.put(@cache_name, key, record.json_payload)
        {:ok, record.json_payload}
    end
  end

  defp encode_entries(values) do
    entries = Enum.map(values, &%{"value" => &1})
    Jason.encode!(%{entries: entries})
  end

  defp build_key(account_handle, project_handle, cas_id) do
    "keyvalue:#{account_handle}:#{project_handle}:#{cas_id}"
  end
end
