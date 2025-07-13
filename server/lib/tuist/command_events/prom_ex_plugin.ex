defmodule Tuist.CommandEvents.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for the Tuist command events.
  """
  use PromEx.Plugin

  alias Tuist.Telemetry

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_runs_event_metrics,
        [
          counter(
            [:tuist, :runs, :total],
            event_name: Telemetry.event_name_run_command(),
            description: "A Tuist run event",
            tags: [:name, :is_ci, :status],
            tag_values: &get_run_tag_values/1
          ),
          distribution(
            [:tuist, :runs, :duration, :milliseconds],
            event_name: Telemetry.event_name_run_command(),
            measurement: :duration,
            unit: :millisecond,
            description: "A Tuist run event duration in milliseconds",
            tags: [:name, :is_ci, :status],
            tag_values: &get_run_tag_values/1,
            reporter_options: [
              buckets: exponential!(100, 2, 15)
            ]
          )
        ]
      ),
      Event.build(
        :tuist_cache_event_metrics,
        [
          sum(
            [:tuist, :cache, :events, :total],
            event_name: Telemetry.event_name_cache(),
            measurement: :count,
            description: "A Tuist cache event",
            tags: [:event_type],
            tag_values: &get_cache_tag_values/1
          )
        ]
      )
    ]
  end

  defp get_run_tag_values(%{command_event: %{name: name, is_ci: is_ci, status: status}}) do
    %{name: name, is_ci: is_ci, status: status}
  end

  defp get_cache_tag_values(%{event_type: event_type}) do
    %{event_type: event_type}
  end
end
