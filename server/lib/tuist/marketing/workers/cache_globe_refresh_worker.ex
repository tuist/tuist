defmodule Tuist.Marketing.Workers.CacheGlobeRefreshWorker do
  @moduledoc """
  Singleton writer for the public cache-globe snapshot.

  Only one incomplete job of this worker may exist cluster-wide (Oban unique).
  Cron on the web leader inserts it about once a minute; web `Stats` pollers
  only *read* the cached snapshot and never take a Redis lock around the
  ClickHouse query. That avoids the multi-replica lock stampede that forced
  the emergency revert of the booth TV page.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [fields: [:worker], period: :infinity, states: :incomplete]

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Marketing.CacheGlobe
  alias Tuist.Marketing.CacheGlobeOrigins

  require Logger

  @cache_key [:marketing, :cache_globe]
  # Longer than the cron interval so readers always have a value between refreshes.
  @cache_ttl to_timeout(second: 120)
  @playback_key "marketing-cache_globe-playback-v1"
  @playback_ttl_seconds 1200

  @impl Oban.Worker
  def perform(_job) do
    snapshot = publish_origins(CacheGlobe.snapshot())

    KeyValueStore.put(@cache_key, snapshot,
      persist_across_deployments: true,
      ttl: @cache_ttl
    )

    :ok
  end

  defp publish_origins(snapshot) do
    if Environment.redis_url() do
      publish_shared_origins(snapshot)
    else
      # Country cells must not be independently re-released by per-replica
      # Cachex stores. Counters can use their usual fallback; live arcs cannot.
      CacheGlobe.with_origins(snapshot, [])
    end
  end

  defp publish_shared_origins(snapshot) do
    conn = Environment.redis_conn_name()

    with {:ok, encoded} <- Redix.command(conn, ["GET", @playback_key], timeout: 5000),
         state = CacheGlobeOrigins.freeze(decode_state(encoded), snapshot.origins, snapshot.updated_at),
         {:ok, _result} <-
           Redix.command(
             conn,
             ["SET", @playback_key, :erlang.term_to_binary(state), "EX", @playback_ttl_seconds],
             timeout: 5000
           ) do
      CacheGlobe.with_origins(snapshot, state.origins)
    else
      {:error, _error} -> origins_unavailable(snapshot)
    end
  rescue
    _error in Redix.ConnectionError -> origins_unavailable(snapshot)
  catch
    :exit, {:noproc, _call} -> origins_unavailable(snapshot)
    :exit, {:timeout, _call} -> origins_unavailable(snapshot)
  end

  defp origins_unavailable(snapshot) do
    Logger.warning("Cache globe playback journal unavailable")
    CacheGlobe.with_origins(snapshot, [])
  end

  defp decode_state(nil), do: nil

  defp decode_state(encoded) do
    case :erlang.binary_to_term(encoded, [:safe]) do
      %{version: 1, since: since, origins: origins} when is_binary(since) and is_list(origins) ->
        if valid_time?(since) and length(origins) <= 10_000 and Enum.all?(origins, &valid_origin?/1) do
          origins =
            Enum.map(
              origins,
              &Map.take(&1, [:location, :region, :window_start, :window_seconds, :playback_delay_seconds, :downloads])
            )

          %{version: 1, since: since, origins: origins}
        end

      _other ->
        nil
    end
  rescue
    _error in ArgumentError -> nil
  end

  defp valid_time?(time) when is_binary(time), do: match?({:ok, _time, 0}, DateTime.from_iso8601(time))
  defp valid_time?(_time), do: false

  defp valid_origin?(%{
         location: location,
         region: region,
         window_start: start,
         window_seconds: seconds,
         playback_delay_seconds: delay,
         downloads: downloads
       }) do
    is_binary(region) and valid_location?(location) and valid_time?(start) and valid_window?(seconds, delay) and
      is_number(downloads) and downloads > 0
  end

  defp valid_origin?(_origin), do: false

  defp valid_location?([lat, lon])
       when is_number(lat) and lat >= -90 and lat <= 90 and is_number(lon) and lon >= -180 and lon <= 180, do: true

  defp valid_location?(_location), do: false

  defp valid_window?(seconds, delay) when is_integer(seconds) and seconds > 0 and seconds <= 300,
    do: delay == max(300, seconds + 240)

  defp valid_window?(_seconds, _delay), do: false
end
