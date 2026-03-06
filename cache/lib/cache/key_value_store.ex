defmodule Cache.KeyValueStore do
  @moduledoc """
  Read-through key-value cache backed by Cachex and persisted to SQLite.
  Provides pre-serialized payloads to minimize response rendering time.
  """

  import Cachex.Spec, only: [expiration: 1]

  alias Cache.KeyValueBuffer
  alias Cache.KeyValueEntry
  alias Cache.Repo

  require Logger

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

  def put_key_value(cas_id, account_handle, project_handle, values, opts \\ []) when is_list(values) do
    key = build_key(account_handle, project_handle, cas_id)
    json = encode_entries(values)
    cache = Keyword.get(opts, :cache_name, @cache_name)

    with :ok <- persist_entry(key, json),
         {:ok, _} <- Cachex.put(cache, key, json) do
      :ok
    end
  end

  @doc """
  Retrieves the pre-encoded JSON payload for a given CAS ID, account, and project.
  Returns `{:error, :not_found}` if no entry is stored.
  """
  def get_key_value(cas_id, account_handle, project_handle, opts \\ []) do
    key = build_key(account_handle, project_handle, cas_id)
    cache = Keyword.get(opts, :cache_name, @cache_name)

    case fetch_entry(key, cache) do
      {:ok, json} -> {:ok, json}
      {:error, :not_found} -> {:error, :not_found}
      {:error, :busy} -> {:error, :busy}
    end
  end

  defp cache_options do
    [
      stats: false,
      expiration: expiration(default: @ttl_ms, interval: to_timeout(minute: 5)),
      backend_options: [read_concurrency: true, write_concurrency: true]
    ]
  end

  defp fetch_entry(key, cache) do
    case Cachex.get(cache, key) do
      {:ok, nil} ->
        load_from_persistence(key, cache)

      {:ok, json} when is_binary(json) ->
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
    load_from_persistence_with_retry(key, cache, 0)
  end

  defp load_from_persistence_with_retry(key, cache, attempt) do
    case Repo.get_by(KeyValueEntry, key: key) do
      nil ->
        {:error, :not_found}

      record ->
        if attempt > 0 do
          Logger.debug("Loaded key-value entry after retry")

          :telemetry.execute(
            [:cache, :kv, :read_through, :retry],
            %{count: attempt},
            %{status: :success}
          )
        end

        Cachex.put(cache, key, record.json_payload)
        KeyValueBuffer.enqueue_access(key)
        {:ok, record.json_payload}
    end
  rescue
    error ->
      handle_persistence_error(key, cache, error, attempt)
  end

  defp handle_persistence_error(key, cache, error, attempt) do
    busy = busy_error?(error)

    if busy and attempt < 3 do
      backoff_ms = 5 * Integer.pow(2, attempt)
      :timer.sleep(backoff_ms)
      load_from_persistence_with_retry(key, cache, attempt + 1)
    else
      if busy do
        Logger.warning("Failed to load key-value entry after retries")

        :telemetry.execute(
          [:cache, :kv, :read_through, :retry],
          %{count: attempt},
          %{status: :exhausted}
        )

        {:error, :busy}
      else
        {:error, :not_found}
      end
    end
  end

  defp busy_error?(error) do
    case error do
      %Exqlite.Error{message: msg} when is_binary(msg) ->
        String.contains?(msg, ["database is locked", "SQLITE_BUSY"])

      _ ->
        false
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
