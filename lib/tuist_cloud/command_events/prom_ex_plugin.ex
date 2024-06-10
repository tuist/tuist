defmodule TuistCloud.CommandEvents.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for the Tuist command events.
  """
  use PromEx.Plugin

  @run_create [:tuist, :run, :command]
  @cache_event [:tuist, :cache, :event]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_runs,
        [
          counter(
            [:tuist, :runs, :total],
            event_name: @run_create,
            description: "A tuist run event",
            tags: [:name, :is_ci, :status],
            tag_values: &get_run_tag_values/1
          ),
          distribution(
            [:tuist, :runs, :duration, :milliseconds],
            event_name: @run_create,
            measurement: :duration,
            unit: :millisecond,
            description: "A tuist run event duration in milliseconds",
            tags: [:name, :is_ci, :status],
            tag_values: &get_run_tag_values/1,
            reporter_options: [
              buckets: exponential!(100, 2, 15)
            ]
          )
        ]
      ),
      Event.build(
        :tuist_cache,
        [
          sum(
            [:tuist, :cache, :events, :total],
            event_name: @cache_event,
            measurement: :count,
            description: "A tuist cache event",
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
