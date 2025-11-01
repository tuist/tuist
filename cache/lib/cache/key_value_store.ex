defmodule Cache.KeyValueStore do
  @moduledoc """
  In-memory storage for cache key-value entries using Cachex.
  Provides pre-serialized payloads to minimize response rendering time.
  """

  import Cachex.Spec, only: [expiration: 1]

  @cache_name :cache_keyvalue_store
  # 1 week
  @ttl_ms :timer.hours(24 * 7)

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
    entry = build_entry(values)

    case Cachex.put(@cache_name, key, entry) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Retrieves the array of values for a given CAS ID, account, and project.
  Returns an empty list if not found.
  """
  def get_key_value(cas_id, account_handle, project_handle) do
    key = build_key(account_handle, project_handle, cas_id)

    case fetch_entry(key) do
      {:ok, %{values: values}} -> values
      :not_found -> []
    end
  end

  @doc """
  Retrieves the pre-encoded JSON payload for a given CAS ID, account, and project.
  Returns `:not_found` if no entry is stored.
  """
  def get_key_value_payload(cas_id, account_handle, project_handle) do
    key = build_key(account_handle, project_handle, cas_id)

    case fetch_entry(key) do
      {:ok, %{json: json}} -> {:ok, json}
      :not_found -> :not_found
    end
  end

  defp cache_options do
    [
      stats: false,
      expiration: expiration(default: @ttl_ms, interval: :timer.minutes(5)),
      backend_options: [read_concurrency: true, write_concurrency: true]
    ]
  end

  defp fetch_entry(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} ->
        :not_found

      {:ok, %{values: _} = entry} ->
        {:ok, entry}

      {:ok, values} when is_list(values) ->
        entry = build_entry(values)
        _ = Cachex.put(@cache_name, key, entry)
        {:ok, entry}

      {:error, _} ->
        :not_found
    end
  end

  defp build_entry(values) do
    %{
      values: values,
      json: encode_entries(values)
    }
  end

  defp encode_entries(values) do
    entries = Enum.map(values, &%{"value" => &1})
    Jason.encode!(%{entries: entries})
  end

  defp build_key(account_handle, project_handle, cas_id) do
    "keyvalue:#{account_handle}:#{project_handle}:#{cas_id}"
  end
end
