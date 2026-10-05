defmodule Tuist.Marketing.CacheGlobe do
  @moduledoc """
  Public, region-level cache download totals. No tenant, project, node, or
  downloader information leaves this context. Locations are representative
  serving-region coordinates, not customer locations or transfer destinations.
  """

  alias Tuist.ClickHouseRepo

  require Logger

  @empty_breakdown %{"all" => nil, "module" => nil, "gradle" => nil, "bazel" => nil}

  # The public managed serving regions (Tuist.Kura.Regions, as enabled in
  # production), each placed at its datacenter's city.
  @regions [
    %{id: "us-west", name: "US West", location: [45.52, -122.99]},
    %{id: "us-central", name: "US Central", location: [41.88, -87.63]},
    %{id: "us-east", name: "US East", location: [38.75, -77.67]},
    %{id: "sa-west", name: "South America West", location: [-33.45, -70.67]},
    %{id: "eu-west", name: "EU West", location: [48.86, 2.35]},
    %{id: "eu-east", name: "EU East", location: [52.23, 21.01]},
    %{id: "ap-southeast", name: "Asia Pacific Southeast", location: [1.35, 103.82]}
  ]

  def empty do
    %{
      downloads: nil,
      bytes: nil,
      recent_downloads: nil,
      breakdown: @empty_breakdown,
      origins: [],
      updated_at: nil,
      observed_at: nil,
      status: :waiting,
      regions: Enum.map(@regions, &Map.merge(&1, %{downloads: 0, recent_downloads: 0}))
    }
  end

  def snapshot(now \\ DateTime.utc_now()) do
    # ClickHouse rejects fractional seconds in DateTime query parameters.
    now = DateTime.truncate(now, :second)
    midnight = now |> DateTime.to_date() |> DateTime.new!(~T[00:00:00])

    rows =
      ClickHouseRepo.query!(
        """
        SELECT region, sum(request_count), sum(bytes),
               sumIf(request_count, window_start >= {recent:DateTime}),
               max(window_start + toIntervalSecond(window_seconds))
        FROM kura_usage_events FINAL
        WHERE window_start >= {midnight:DateTime} AND window_start < {now:DateTime}
          AND traffic_plane = 'public' AND direction = 'egress' AND operation = 'download'
          AND region IN {regions:Array(String)}
        GROUP BY region
        """,
        %{
          "midnight" => DateTime.to_naive(midnight),
          "now" => DateTime.to_naive(now),
          "recent" => now |> DateTime.add(-300, :second) |> DateTime.to_naive(),
          "regions" => Enum.map(@regions, & &1.id)
        },
        timeout: 15_000,
        settings: [max_execution_time: 10, max_threads: 2, max_memory_usage: 268_435_456]
      ).rows

    by_region =
      Map.new(rows, fn [id, downloads, bytes, recent, observed] -> {id, {downloads, bytes, recent, observed}} end)

    regions =
      Enum.map(@regions, fn region ->
        {downloads, _bytes, recent, _observed} = Map.get(by_region, region.id, {0, 0, 0, nil})
        Map.merge(region, %{downloads: downloads, recent_downloads: recent})
      end)

    observed_at = rows |> Enum.map(&List.last/1) |> Enum.max(NaiveDateTime, fn -> nil end)

    %{
      downloads: Enum.sum(Enum.map(rows, &Enum.at(&1, 1))),
      bytes: Enum.sum(Enum.map(rows, &Enum.at(&1, 2))),
      recent_downloads: Enum.sum(Enum.map(rows, &Enum.at(&1, 3))),
      breakdown: breakdown(midnight, now),
      # Where requests come from (each a location, its serving region and its
      # recent count). Empty until the usage rollups record a request's
      # country; the page draws nothing invented in its place.
      origins: [],
      updated_at: DateTime.to_iso8601(now),
      observed_at: if(observed_at, do: NaiveDateTime.to_iso8601(observed_at) <> "Z"),
      status: if(observed_at, do: :available, else: :waiting),
      regions: regions
    }
  end

  defp breakdown(midnight, now) do
    sources = [
      {"module",
       """
       SELECT sum(local_cache_hits_count + remote_cache_hits_count), sum(cacheable_targets_count)
       FROM command_events
       WHERE ran_at >= {midnight:DateTime} AND ran_at < {now:DateTime} AND name = 'generate'
       """},
      {"gradle",
       """
       SELECT sum(tasks_local_hit_count + tasks_remote_hit_count + tasks_cache_hit_count),
              sum(cacheable_tasks_count)
       FROM gradle_builds
       WHERE inserted_at >= {midnight:DateTime} AND inserted_at < {now:DateTime}
       """},
      {"bazel",
       """
       SELECT countIf(outcome = 'hit'), count()
       FROM reapi_cache_events
       WHERE inserted_at >= {midnight:DateTime} AND inserted_at < {now:DateTime}
         AND client_kind = 'bazel' AND operation = 'action_cache' AND outcome IN ('hit', 'miss')
       """}
    ]

    counts =
      Enum.map(sources, fn {kind, query} ->
        result =
          ClickHouseRepo.query(
            query,
            %{"midnight" => DateTime.to_naive(midnight), "now" => DateTime.to_naive(now)},
            timeout: 15_000,
            settings: [
              max_execution_time: 10,
              max_threads: 2,
              max_memory_usage: 268_435_456,
              max_rows_to_read: 5_000_000,
              read_overflow_mode: "throw"
            ]
          )

        case result do
          {:ok, %{rows: [[hits, total]]}} ->
            {kind, {min(hits, total), total}}

          {:error, error} ->
            Logger.warning("Cache globe #{kind} hit rate unavailable: #{inspect(error)}")
            {kind, nil}
        end
      end)

    rates =
      Map.new(counts, fn
        {kind, nil} -> {kind, nil}
        {kind, {hits, total}} -> {kind, hit_rate(hits, total)}
      end)

    overall =
      if Enum.all?(counts, fn {_kind, count} -> count != nil end) do
        hits = Enum.sum(Enum.map(counts, fn {_kind, {hits, _total}} -> hits end))
        total = Enum.sum(Enum.map(counts, fn {_kind, {_hits, total}} -> total end))
        hit_rate(hits, total)
      end

    Map.put(rates, "all", overall)
  end

  defp hit_rate(_hits, 0), do: nil
  defp hit_rate(hits, total), do: hits / total * 100
end
