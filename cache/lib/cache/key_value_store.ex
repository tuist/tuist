defmodule Cache.KeyValueStore do
  @moduledoc """
  Read-through key-value cache backed by Cachex and persisted to SQLite.
  Provides pre-serialized payloads to minimize response rendering time.
  """

  import Cachex.Spec, only: [expiration: 1, limit: 1]

  alias Cache.Config
  alias Cache.DistributedKV.Entry, as: DistributedEntry
  alias Cache.DistributedKV.Repo, as: DistributedRepo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueBuffer
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueRepo
  alias Cache.SQLiteHelpers

  @cache_name :cache_keyvalue_store
  @contention_event [:cache, :kv, :get, :contention]
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
        load_from_persistence_or_remote(key, cache)

      {:ok, json} when is_binary(json) ->
        if Config.distributed_kv_enabled?(), do: maybe_track_access(key)
        {:ok, json}

      {:ok, _} ->
        {:error, :not_found}

      {:error, _} ->
        load_from_persistence_or_remote(key, cache)
    end
  end

  defp persist_entry(key, json) do
    :ok = KeyValueBuffer.enqueue(key, json)
  end

  defp load_from_persistence_or_remote(key, cache) do
    with_repo_busy_timeout(Config.key_value_read_busy_timeout_ms(), fn ->
      case KeyValueRepo.get_by(KeyValueEntry, key: key) do
        nil ->
          maybe_load_from_remote(key, cache)

        record ->
          Cachex.put(cache, key, record.json_payload)

          if Config.distributed_kv_enabled?() and not is_nil(record.source_updated_at) do
            KeyValueAccessTracker.mark_shared_lineage(key)
          end

          maybe_track_access(key)
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
    if Config.distributed_kv_enabled?() do
      if KeyValueAccessTracker.shared_lineage?(key) and KeyValueAccessTracker.allow_access_bump?(key) do
        KeyValueBuffer.enqueue_access(key)
      end
    else
      KeyValueBuffer.enqueue_access(key)
    end

    :ok
  end

  defp maybe_load_from_remote(key, cache) do
    if Config.distributed_kv_enabled?() and Config.distributed_kv_remote_fallback_enabled?() do
      case DistributedRepo.get_by(DistributedEntry, key: key, deleted_at: nil) do
        %DistributedEntry{} = entry ->
          materialize_remote_hit(entry, cache)

        nil ->
          {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  defp materialize_remote_hit(entry, cache) do
    local_attrs = %{
      key: entry.key,
      json_payload: entry.json_payload,
      last_accessed_at: entry.last_accessed_at,
      source_updated_at: entry.source_updated_at
    }

    _ = KeyValueEntries.materialize_remote_entry(local_attrs)
    :ok = KeyValueAccessTracker.mark_shared_lineage(entry.key)
    {:ok, _} = Cachex.put(cache, entry.key, entry.json_payload)
    maybe_track_access(entry.key)
    {:ok, entry.json_payload}
  end

  defp encode_entries(values) do
    entries = Enum.map(values, &%{"value" => &1})
    Jason.encode!(%{entries: entries})
  end

  defp build_key(account_handle, project_handle, cas_id) do
    "keyvalue:#{account_handle}:#{project_handle}:#{cas_id}"
  end
end
