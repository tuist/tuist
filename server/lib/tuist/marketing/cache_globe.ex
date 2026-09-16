defmodule Tuist.Marketing.CacheGlobe do
  @moduledoc """
  Public, region-level cache download totals. No tenant, project, node, or
  downloader information leaves this context. Locations are representative
  serving-region coordinates, not customer locations or transfer destinations.
  """

  alias Tuist.ClickHouseRepo

  @regions [
    %{id: "us-west", name: "North America West", location: [45.52, -122.99]},
    %{id: "us-east", name: "North America East", location: [38.75, -77.67]},
    %{id: "eu-central", name: "Europe", location: [48.86, 2.35]},
    %{id: "ap-southeast", name: "Asia Pacific", location: [1.35, 103.82]},
    %{id: "sa-west", name: "South America", location: [-33.45, -70.67]}
  ]

  def empty do
    %{
      downloads: nil,
      bytes: nil,
      recent_downloads: nil,
      updated_at: nil,
      observed_at: nil,
      status: :waiting,
      regions: Enum.map(@regions, &Map.merge(&1, %{downloads: 0, recent_downloads: 0}))
    }
  end

  def snapshot(now \\ DateTime.utc_now()) do
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
      updated_at: DateTime.to_iso8601(now),
      observed_at: if(observed_at, do: NaiveDateTime.to_iso8601(observed_at) <> "Z"),
      status: if(observed_at, do: :available, else: :waiting),
      regions: regions
    }
  end
end
