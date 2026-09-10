defmodule Tuist.Bazel.Timeline do
  @moduledoc """
  Timeline metadata from Kura's bounded, retained Build Event Protocol action spans.
  No per-action outcome, log or machine sample is inferred from invocation-level data.
  """

  alias Tuist.Bazel.Profile

  def load(invocation) do
    Profile.load(invocation) || retained_summary(invocation)
  end

  defp retained_summary(invocation) do
    events =
      [
        invocation.build_timeline_span_start_ms,
        invocation.build_timeline_span_durations_ms,
        invocation.build_timeline_span_categories,
        invocation.build_timeline_span_descriptions
      ]
      |> Enum.zip()
      |> Enum.with_index()
      |> Enum.flat_map(fn {{start, duration, category, title}, index} ->
        if duration > 0 do
          [
            %{
              event_id: to_string(index),
              title: title,
              project: invocation.project_handle,
              target: "",
              category: category,
              start_ms: start,
              duration_ms: duration,
              status: "unknown"
            }
          ]
        else
          []
        end
      end)
      |> Enum.sort_by(&{&1.start_ms, &1.event_id})

    duration =
      Enum.reduce(
        events,
        max(invocation.duration_ms, invocation.build_timeline_duration_ms),
        &max(&2, &1.start_ms + &1.duration_ms)
      )

    %{
      events: events,
      total_count: length(events),
      duration: max(duration, 1),
      target_count: nil,
      has_metrics: false,
      machine_metrics: [],
      local_navigation: true,
      logs_available: false,
      time_origin: "build_start",
      coverage: "retained_action_spans"
    }
  end
end
