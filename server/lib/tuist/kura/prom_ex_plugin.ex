defmodule Tuist.Kura.PromExPlugin do
  @moduledoc """
  Metrics for the demand-driven Kura lifecycle.

  Event metrics come off the transitions themselves
  (`Tuist.Kura.Telemetry`): cold-return rate, time-to-ready on cold return,
  reclaimed bytes, archive cancellations, refused provisions, and the accounts
  refused a service region before they reach any transition at all.

  Two polled gauges cover what a transition cannot see:

    * per-region occupancy — the forecast enforced warm quota against what is
      installed. This is the number that decides whether another machine is
      needed, and whether the Air pressure rule is active at all.
    * hit-rate recovery — the cache hit ratio of account-regions that returned
      from archive recently, against the same ratio for instances that did
      not. A cold return that never recovers its hit rate is the cost the
      inactivity windows are trading against.

  Both are tagged by region only. Account never appears as a tag.
  """

  use PromEx.Plugin

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.Kura.AccountRegionLifecycle
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Telemetry
  alias Tuist.Repo

  @metric_prefix [:tuist, :kura, :lifecycle]
  @poll_rate to_timeout(minute: 1)

  # A cold return's time-to-ready spans a provision plus a rollout, so the
  # buckets run from a fast reschedule to well past a slow image pull.
  @ready_buckets [
    30_000,
    60_000,
    120_000,
    300_000,
    600_000,
    900_000,
    1_800_000,
    3_600_000
  ]

  # How long after a return an account-region still counts as recovering. The
  # hit rate of an instance that returned last month is just its hit rate.
  @recovery_window_days 7

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_kura_lifecycle_event_metrics,
        [
          counter(
            @metric_prefix ++ [:provisioned, :count],
            event_name: Telemetry.event_name_provisioned(),
            description: "Kura account-region instances provisioned, split by whether this was a return from archive.",
            tags: [:plan, :region, :cold_return]
          ),
          distribution(
            @metric_prefix ++ [:time_to_ready, :milliseconds],
            event_name: Telemetry.event_name_ready(),
            measurement: :time_to_ready_ms,
            description: "Wall-clock from provisioning an instance to it serving cache traffic.",
            reporter_options: [buckets: @ready_buckets],
            tags: [:plan, :region, :cold_return],
            unit: :millisecond
          ),
          counter(
            @metric_prefix ++ [:drain_pending, :count],
            event_name: Telemetry.event_name_drain_pending(),
            description: "Instances entering drain-pending, split by whether capacity pressure shortened the window.",
            tags: [:plan, :region, :reason]
          ),
          counter(
            @metric_prefix ++ [:archive_cancelled, :count],
            event_name: Telemetry.event_name_archive_cancelled(),
            description: "Archivals cancelled because cache demand returned mid-drain.",
            tags: [:plan, :region]
          ),
          counter(
            @metric_prefix ++ [:archived, :count],
            event_name: Telemetry.event_name_archived(),
            description: "Instances archived after a successful drain.",
            tags: [:plan, :region]
          ),
          sum(
            @metric_prefix ++ [:reclaimed, :bytes],
            event_name: Telemetry.event_name_archived(),
            measurement: :reclaimed_bytes,
            description: "Enforced warm quota reclaimed by archival.",
            tags: [:plan, :region]
          ),
          distribution(
            @metric_prefix ++ [:drain_duration, :milliseconds],
            event_name: Telemetry.event_name_archived(),
            measurement: :drain_duration_ms,
            description: "Wall-clock an archived instance spent in drain-pending.",
            reporter_options: [buckets: @ready_buckets],
            tags: [:plan, :region],
            unit: :millisecond
          ),
          counter(
            @metric_prefix ++ [:resolution_refused, :count],
            event_name: Telemetry.event_name_resolution_refused(),
            description: "Accounts refused a service region, so they never enter the lifecycle at all.",
            tags: [:plan, :reason]
          ),
          counter(
            @metric_prefix ++ [:placement_preference_unmet, :count],
            event_name: Telemetry.event_name_placement_preference_unmet(),
            description:
              "Placements served further from the traffic than they could be, because the nearest " <>
                "region is unserved or carries no budget for the plan. The procurement signal: " <>
                "sustained counts on one wanted/served pair are the case for funding that region.",
            tags: [:origin, :wanted, :served]
          ),
          counter(
            @metric_prefix ++ [:origin_attribution, :count],
            event_name: Telemetry.event_name_origin_attribution(),
            description:
              "Requests placement tried to attribute, by whether the edge could place them. " <>
                "An edge that stops reporting locations otherwise looks exactly like a quiet " <>
                "fleet, with placement silently falling back to the default region.",
            tags: [:signal, :attributed]
          )
        ]
      )
    ]
  end

  @impl true
  def polling_metrics(_opts) do
    [
      Polling.build(
        :tuist_kura_capacity_polling_metrics,
        @poll_rate,
        {__MODULE__, :execute_occupancy_telemetry_event, []},
        [
          last_value(
            [:tuist, :kura, :capacity, :reserved, :gibibytes],
            event_name: [:tuist, :kura, :capacity, :occupancy],
            measurement: :reserved_gib,
            description: "Disk the region's cache pods have reserved.",
            tags: [:region]
          ),
          last_value(
            [:tuist, :kura, :capacity, :allocatable, :gibibytes],
            event_name: [:tuist, :kura, :capacity, :occupancy],
            measurement: :allocatable_gib,
            description: "Allocatable disk across the region's Ready nodes.",
            tags: [:region]
          ),
          last_value(
            [:tuist, :kura, :capacity, :instances, :count],
            event_name: [:tuist, :kura, :capacity, :occupancy],
            measurement: :instances,
            description: "Live Kura instances in the region.",
            tags: [:region]
          )
        ]
      ),
      Polling.build(
        :tuist_kura_recovery_polling_metrics,
        @poll_rate,
        {__MODULE__, :execute_hit_rate_recovery_telemetry_event, []},
        [
          last_value(
            @metric_prefix ++ [:returned_hit_rate, :ratio],
            event_name: [:tuist, :kura, :lifecycle, :hit_rate_recovery],
            measurement: :returned_hit_rate,
            description: "Cache hit ratio of account-regions that returned from archive in the recovery window.",
            tags: [:region]
          ),
          last_value(
            @metric_prefix ++ [:steady_hit_rate, :ratio],
            event_name: [:tuist, :kura, :lifecycle, :hit_rate_recovery],
            measurement: :steady_hit_rate,
            description: "Cache hit ratio of account-regions that did not recently return, for comparison.",
            tags: [:region]
          )
        ]
      )
    ]
  end

  @doc false
  def execute_occupancy_telemetry_event do
    Enum.each(lifecycle_regions(), fn %Regions{id: region_id} ->
      occupancy = Capacity.occupancy(region_id)

      :telemetry.execute(
        [:tuist, :kura, :capacity, :occupancy],
        %{
          # A region whose cluster cannot be read reports zero rather than
          # skipping the series, so it is visibly at zero instead of holding
          # its last good sample forever.
          reserved_gib: occupancy.reserved_gib || 0,
          allocatable_gib: occupancy.allocatable_gib || 0,
          instances: occupancy.instances
        },
        %{region: region_id}
      )
    end)
  end

  @doc false
  def execute_hit_rate_recovery_telemetry_event do
    Enum.each(lifecycle_regions(), &execute_region_hit_rate_recovery(&1.id))
  end

  defp execute_region_hit_rate_recovery(region_id) do
    returned_account_ids = recently_returned_account_ids(region_id)
    hit_rates = hit_rates_by_account(region_id)

    {returned, steady} =
      Enum.split_with(hit_rates, fn {account_id, _rate} -> MapSet.member?(returned_account_ids, account_id) end)

    :telemetry.execute(
      [:tuist, :kura, :lifecycle, :hit_rate_recovery],
      %{returned_hit_rate: mean_rate(returned), steady_hit_rate: mean_rate(steady)},
      %{region: region_id}
    )
  end

  defp recently_returned_account_ids(region_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@recovery_window_days * 86_400, :second)

    AccountRegionLifecycle
    |> where([l], l.service_region == ^region_id)
    |> where([l], not is_nil(l.last_returned_at) and l.last_returned_at >= ^cutoff)
    |> select([l], l.account_id)
    |> Repo.all()
    |> MapSet.new()
  end

  # A download is content the instance already had; an upload is the store
  # that follows a miss. Their ratio over the recovery window is the closest
  # thing to a hit rate the usage rollups carry, and it is the same
  # measurement for a returned instance and a steady one, so the comparison
  # between them is meaningful even where the absolute number is a proxy.
  defp hit_rates_by_account(region_id) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-@recovery_window_days * 86_400, :second)
      |> DateTime.truncate(:second)

    Enum.map(
      ClickHouseRepo.query!(
        """
        SELECT account_id,
               sum(if(operation = 'download', request_count, 0)) AS hits,
               sum(request_count) AS total
        FROM kura_usage_events
        WHERE region = {region:String} AND window_start >= {since:DateTime} AND account_id != 0
        GROUP BY account_id
        HAVING total > 0
        """,
        %{"region" => region_id, "since" => DateTime.to_naive(since)}
      ).rows,
      fn [account_id, hits, total] -> {account_id, hits / total} end
    )
  end

  defp mean_rate([]), do: 0.0

  defp mean_rate(rates) do
    Enum.sum(Enum.map(rates, fn {_account_id, rate} -> rate end)) / length(rates)
  end

  defp lifecycle_regions do
    if Environment.tuist_hosted?() do
      Enum.reject(Regions.available(), &Regions.private?/1)
    else
      []
    end
  end
end
