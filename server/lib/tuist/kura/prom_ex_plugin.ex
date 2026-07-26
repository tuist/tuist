defmodule Tuist.Kura.PromExPlugin do
  @moduledoc """
  PromEx plugin for the Kura fleet rollout (spec #79).

  Polling-only: every 30s the poll reads the rollout state and the
  fleet's version distribution from Postgres and emits gauges. Grafana is
  the paging authority on top of these series — rollout paused sustained
  (page), rollout active too long (warn), and rollout metrics absent
  while a rollout was recently active (page, the case in-band alerting
  structurally misses: a control plane that dies mid-rollout stops
  reporting instead of raising a paused signal).

  The `rollout_active` gauge is emitted every poll — 1 while a rollout is
  running or paused, 0 otherwise — precisely so that absence of the
  series is distinguishable from an idle fleet.

  Cardinality: `image_tag` is bounded by the handful of tags live in the
  fleet at once; ended rollouts and drained tags emit one final zero so
  `last_value` doesn't hold stale series forever.
  """

  use PromEx.Plugin

  alias Tuist.Kura.Rollout
  alias Tuist.Kura.Rollouts
  alias Tuist.Repo
  alias TuistCommon.Repo.PoolMetrics

  @metric_prefix [:tuist, :kura]

  @rollout_event [:tuist, :kura, :rollout, :status]
  @fleet_event [:tuist, :kura, :fleet, :versions]

  # Process-dict keys remembering the label sets emitted on the previous
  # poll, so a rollout that ends (or an image tag that drains from the
  # fleet) gets one explicit zero instead of a stale `last_value` series.
  @rollout_seen_key :tuist_kura_rollout_seen_tags
  @fleet_seen_key :tuist_kura_fleet_seen_tags

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, to_timeout(second: 30))

    [
      Polling.build(
        :tuist_kura_rollout_metrics,
        poll_rate,
        {__MODULE__, :execute_rollout_telemetry_event, []},
        [
          last_value(
            @metric_prefix ++ [:rollout, :active],
            event_name: @rollout_event,
            description: "1 while a Kura rollout is running or paused for the tag, 0 otherwise.",
            measurement: :active,
            tags: [:image_tag, :mode]
          ),
          last_value(
            @metric_prefix ++ [:rollout, :paused],
            event_name: @rollout_event,
            description: "1 while the Kura rollout of the tag is paused.",
            measurement: :paused,
            tags: [:image_tag, :mode]
          ),
          last_value(
            @metric_prefix ++ [:rollout, :wave],
            event_name: @rollout_event,
            description: "Current wave of the Kura rollout of the tag.",
            measurement: :wave,
            tags: [:image_tag, :mode]
          ),
          last_value(
            @metric_prefix ++ [:rollout, :wave, :age, :seconds],
            event_name: @rollout_event,
            description: "Seconds since the Kura rollout's current wave opened (0 between waves).",
            measurement: :wave_age_seconds,
            tags: [:image_tag, :mode]
          ),
          last_value(
            @metric_prefix ++ [:rollout, :servers, :scoped],
            event_name: @rollout_event,
            description: "Servers scoped into the Kura rollout so far (one row per server, replicas not double-counted).",
            measurement: :scoped_servers,
            tags: [:image_tag, :mode]
          ),
          last_value(
            @metric_prefix ++ [:rollout, :servers, :converged],
            event_name: @rollout_event,
            description: "Scoped servers observed on the rollout's target image.",
            measurement: :converged_servers,
            tags: [:image_tag, :mode]
          )
        ]
      ),
      Polling.build(
        :tuist_kura_fleet_version_metrics,
        poll_rate,
        {__MODULE__, :execute_fleet_versions_telemetry_event, []},
        [
          last_value(
            @metric_prefix ++ [:fleet, :servers],
            event_name: @fleet_event,
            description: "Non-destroyed Kura servers per observed image tag (the version-convergence curve).",
            measurement: :count,
            tags: [:image_tag]
          )
        ]
      )
    ]
  end

  def execute_rollout_telemetry_event do
    if PoolMetrics.running?(Repo) do
      rollout = Rollouts.latest_rollout()
      current = emit_rollout(rollout)

      @rollout_seen_key
      |> Process.get(MapSet.new())
      |> MapSet.difference(current)
      |> Enum.each(fn {image_tag, mode} ->
        :telemetry.execute(
          @rollout_event,
          %{active: 0, paused: 0, wave: 0, wave_age_seconds: 0, scoped_servers: 0, converged_servers: 0},
          %{image_tag: image_tag, mode: mode}
        )
      end)

      Process.put(@rollout_seen_key, current)
    end
  end

  defp emit_rollout(nil), do: MapSet.new()

  defp emit_rollout(%Rollout{} = rollout) do
    summary = Rollouts.wave_summary(rollout)
    scoped = summary |> Enum.map(& &1.servers) |> Enum.sum()
    converged = summary |> Enum.map(& &1.converged) |> Enum.sum()

    wave_age_seconds =
      case rollout.wave_started_at do
        nil -> 0
        started_at -> max(DateTime.diff(DateTime.utc_now(), started_at, :second), 0)
      end

    labels = %{image_tag: rollout.image_tag, mode: Atom.to_string(rollout.mode)}

    :telemetry.execute(
      @rollout_event,
      %{
        active: if(rollout.status in [:running, :paused], do: 1, else: 0),
        paused: if(rollout.status == :paused, do: 1, else: 0),
        wave: rollout.current_wave,
        wave_age_seconds: wave_age_seconds,
        scoped_servers: scoped,
        converged_servers: converged
      },
      labels
    )

    MapSet.new([{labels.image_tag, labels.mode}])
  end

  def execute_fleet_versions_telemetry_event do
    if PoolMetrics.running?(Repo) do
      distribution = Rollouts.fleet_version_distribution()
      current = distribution |> Map.keys() |> MapSet.new()

      Enum.each(distribution, fn {image_tag, count} ->
        :telemetry.execute(@fleet_event, %{count: count}, %{image_tag: image_tag})
      end)

      @fleet_seen_key
      |> Process.get(MapSet.new())
      |> MapSet.difference(current)
      |> Enum.each(fn image_tag ->
        :telemetry.execute(@fleet_event, %{count: 0}, %{image_tag: image_tag})
      end)

      Process.put(@fleet_seen_key, current)
    end
  end
end
