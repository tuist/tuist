defmodule Cache.KeyValueStore do
  @moduledoc """
  In-memory storage for cache key-value entries using Cachex.
  Configured with a 1GB memory limit.
  """

  @cache_name :cache_keyvalue_store
  # 1 week
  @ttl_ms :timer.hours(24 * 7)

  @doc """
  Starts the cache with the configured settings.
  Should be called from the application supervisor.
  """
  def start_link(_opts) do
    Cachex.start_link(@cache_name, stats: true)
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

    # Store with TTL
    case Cachex.put(@cache_name, key, values, ttl: @ttl_ms) do
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

    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> []
      {:ok, values} -> values
      {:error, _} -> []
    end
  end

  defp build_key(account_handle, project_handle, cas_id) do
    "keyvalue:#{account_handle}:#{project_handle}:#{cas_id}"
  end
end
