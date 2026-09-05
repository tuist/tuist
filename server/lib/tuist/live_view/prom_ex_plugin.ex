defmodule Tuist.LiveView.PromExPlugin do
  @moduledoc """
  Prometheus histogram of how long the function handed to `assign_async` runs
  in each LiveView, by outcome.

  HTTP request metrics only see a LiveView's initial render; the data the page
  shows is loaded afterwards over the socket, so this is where a slow or
  failing page shows up. The event is emitted by `TuistWeb.Async`.
  """
  use PromEx.Plugin

  alias Tuist.Telemetry

  @metric_prefix [:tuist, :live_view, :assign_async]

  @duration_buckets [100, 250, 500, 1_000, 2_500, 5_000, 10_000, 20_000, 30_000, 60_000]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_live_view_assign_async_event_metrics,
        [
          distribution(
            @metric_prefix ++ [:duration, :milliseconds],
            event_name: Telemetry.event_name_live_view_assign_async(),
            measurement: :duration,
            description: "Wall-clock of the function passed to assign_async in a LiveView, by view and outcome.",
            reporter_options: [buckets: @duration_buckets],
            tag_values: &tag_values/1,
            tags: [:view, :result],
            unit: {:native, :millisecond}
          )
        ]
      )
    ]
  end

  def tag_values(%{view: view, result: result}) do
    %{view: inspect(view), result: Atom.to_string(result)}
  end
end
