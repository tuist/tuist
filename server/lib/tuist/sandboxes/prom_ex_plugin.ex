defmodule Tuist.Sandboxes.PromExPlugin do
  @moduledoc "Sandbox capacity outcomes, bounded by node and operation; no account or session labels."
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(:sandbox_capacity, [
        counter([:tuist, :sandboxes, :capacity, :operations, :total],
          event_name: [:tuist, :sandboxes, :capacity],
          tags: [:node, :operation, :outcome],
          description: "Sandbox capacity operations by outcome."
        ),
        distribution([:tuist, :sandboxes, :capacity, :duration, :milliseconds],
          event_name: [:tuist, :sandboxes, :capacity],
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:node, :operation, :outcome],
          reporter_options: [buckets: [10, 50, 100, 250, 500, 1000, 2500, 5000, 15_000]],
          description: "Sandbox growth admission and reclaim latency."
        )
      ])
    ]
  end
end
