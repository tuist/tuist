defmodule Cache.KeyValueStore do
  @moduledoc """
  Read-through key-value cache backed by Cachex and persisted to SQLite.
  Provides pre-serialized payloads to minimize response rendering time.
  """

  import Cachex.Spec, only: [expiration: 1, limit: 1]

  alias Cache.Config
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueBuffer
  alias Cache.KeyValueEntry
  alias Cache.KeyValueRepo
  alias Cache.SQLiteHelpers

  @cache_name :cache_keyvalue_store
  @contention_event [:cache, :kv, :get, :contention]

  def cache_name, do: @cache_name
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

  def put_key_value(cas_id, account_handle, project_handle, values, opts \\ []) when is_list(values) do
    key = build_key(account_handle, project_handle, cas_id)
    json = encode_entries(values)
    cache = Keyword.get(opts, :cache_name, @cache_name)

    with :ok <- persist_entry(key, json),
         {:ok, _} <- Cachex.put(cache, key, json) do
      if Config.distributed_kv_enabled?(), do: KeyValueAccessTracker.mark_shared_lineage(key)
      :ok
    end
  end

  @doc """
  Retrieves the pre-encoded JSON payload for a given CAS ID, account, and project.
  Returns `{:error, :not_found}` if no entry is stored or if the SQLite database
  is under lock contention (contention is absorbed as a cache miss to avoid
  blocking request serving).
  """
  def get_key_value(cas_id, account_handle, project_handle, opts \\ []) do
    key = build_key(account_handle, project_handle, cas_id)
    cache = Keyword.get(opts, :cache_name, @cache_name)

    fetch_entry(key, cache)
  end

  defp cache_options do
    [
      stats: false,
      expiration: expiration(default: @ttl_ms, interval: to_timeout(minute: 5)),
      limit: limit(size: 100_000, policy: Cachex.Policy.LRW, reclaim: 0.1),
      backend_options: [read_concurrency: true, write_concurrency: true]
    ]
  end

  defp fetch_entry(key, cache) do
    case Cachex.get(cache, key) do
      {:ok, nil} ->
        load_from_persistence(key, cache)

      {:ok, json} when is_binary(json) ->
        if Config.distributed_kv_enabled?(), do: maybe_track_access(key)
        {:ok, json}

      {:ok, _} ->
        {:error, :not_found}

      {:error, _} ->
        load_from_persistence(key, cache)
    end
  end

  defp persist_entry(key, json) do
    :ok = KeyValueBuffer.enqueue(key, json)
  end

  defp load_from_persistence(key, cache) do
    with_repo_busy_timeout(Config.key_value_read_busy_timeout_ms(), fn ->
      case KeyValueRepo.get_by(KeyValueEntry, key: key) do
        nil ->
          {:error, :not_found}

        record ->
          Cachex.put(cache, key, record.json_payload)

          if Config.distributed_kv_enabled?() and not is_nil(record.source_updated_at) do
            KeyValueAccessTracker.mark_shared_lineage(key)
          end

          KeyValueBuffer.enqueue_access(key)
          {:ok, record.json_payload}
      end
    end)
  rescue
    error ->
      if SQLiteHelpers.busy_error?(error) do
        :telemetry.execute(@contention_event, %{count: 1}, %{})
        {:error, :not_found}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp with_repo_busy_timeout(timeout_ms, fun) do
    SQLiteHelpers.with_repo_busy_timeout(KeyValueRepo, timeout_ms, fun)
  end

  defp maybe_track_access(key) do
    if KeyValueAccessTracker.shared_lineage?(key) and KeyValueAccessTracker.allow_access_bump?(key) do
      KeyValueBuffer.enqueue_access(key)
    end

    :ok
  end

  defp encode_entries(values) do
    entries = Enum.map(values, &%{"value" => &1})
    JSON.encode!(%{entries: entries})
  end

  defp build_key(account_handle, project_handle, cas_id) do
    "keyvalue:#{account_handle}:#{project_handle}:#{cas_id}"
  end
end
