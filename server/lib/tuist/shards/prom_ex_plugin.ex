defmodule Tuist.Shards.PromExPlugin do
  @moduledoc """
  Which store shard plans go to and how long their uploads take, by store and
  by the verified runner's platform and site; no account or plan labels.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(:tuist_shards_storage, [
        counter([:tuist, :shards, :plans, :total],
          event_name: [:tuist, :shards, :plan, :created],
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
end
