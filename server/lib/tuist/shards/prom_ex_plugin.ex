defmodule Tuist.Shards.PromExPlugin do
  @moduledoc """
  Which store shard plans go to and how long their uploads take, by store and
  by the verified runner's platform and site; no account or plan labels.
  """
  use PromEx.Plugin

  alias Tuist.Shards.Storage

  @plan_created [:tuist, :shards, :plan, :created]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(:tuist_shards_storage, [
        # A sum rather than a counter, so the zero-count events below publish
        # every possible series before its first plan; increase() never sees
        # a series' first plan otherwise.
        sum([:tuist, :shards, :plans, :total],
          event_name: @plan_created,
          measurement: :count,
          tags: [:store, :platform, :site],
          description: "Shard plans created, by the store they were placed in."
        ),
        distribution([:tuist, :shards, :upload, :plan_age, :milliseconds],
          event_name: [:tuist, :shards, :upload, :completed],
          measurement: :plan_age,
          unit: :millisecond,
          tags: [:store, :platform, :site],
          reporter_options: [buckets: [1000, 5000, 15_000, 30_000, 60_000, 120_000, 300_000, 600_000, 1_800_000]],
          description: "Time from a shard plan's creation to each of its artifact uploads completing, by store."
        )
      ])
    ]
  end

  @impl true
  def polling_metrics(opts) do
    [
      Polling.build(
        :tuist_shards_storage_placements,
        Keyword.get(opts, :poll_rate, to_timeout(minute: 5)),
        {__MODULE__, :publish_placements, []},
        []
      )
    ]
  end

  def publish_placements do
    :telemetry.execute(@plan_created, %{count: 0}, %{store: "default", platform: "none", site: "none"})
    for tags <- Storage.placement_tags(), do: :telemetry.execute(@plan_created, %{count: 0}, tags)
  end
end
