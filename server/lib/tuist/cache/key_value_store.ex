defmodule Tuist.Cache.KeyValueStore do
  @moduledoc """
  In-memory storage for cache key-value entries using Cachex.
  Configured with a 1GB memory limit.
  """

  @cache_name :tuist_keyvalue_cache
  @ttl_ms :timer.hours(24) # Default TTL of 24 hours

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
  Stores an array of values for a given CAS ID and project ID.
  Overwrites any existing values.
  """
  def put_key_value(cas_id, project_id, values) when is_list(values) do
    key = build_key(cas_id, project_id)

    # Store with TTL
    case Cachex.put(@cache_name, key, values, ttl: @ttl_ms) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Retrieves the array of values for a given CAS ID and project ID.
  Returns an empty list if not found.
  """
  def get_key_value(cas_id, project_id) do
    key = build_key(cas_id, project_id)

    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> []
      {:ok, values} -> values
      {:error, _} -> []
    end
  end

  # Private functions

  defp build_key(cas_id, project_id) do
    "#{project_id}:#{cas_id}"
  end

end
